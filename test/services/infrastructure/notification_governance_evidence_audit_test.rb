# frozen_string_literal: true

require "test_helper"
require "stringio"
require "json"
require "digest"
require "logger"

module Infrastructure
  class NotificationGovernanceEvidenceAuditTest <
    ActiveSupport::TestCase

    Audit = NotificationGovernanceEvidenceAudit

    setup do
      @output = StringIO.new
      @logger = Logger.new(@output)

      @logger.formatter = proc do |severity, _time, _name, message|
        "#{severity}|#{message}\n"
      end

      @time = Time.utc(2026, 11, 25, 12, 30, 0)

      @audit = Audit.new(
        actor: "herga-test-auditor",
        roles: [:auditor],
        request_id: "evidence-audit-test",
        logger: @logger,
        clock: -> { @time }
      )

      @data = "metric,value\nconfidential-test-value,1\n"
    end

    test "generated event contains expected schema" do
      result = generate_event

      assert_equal %i[
        event timestamp_utc actor roles request_id
        export_type section outcome bytes sha256
      ].sort, result.keys.sort
    end

    test "generated event has correct classification" do
      assert_equal "governance_evidence_export",
                   generate_event[:event]
    end

    test "generated event identifies actor" do
      assert_equal "herga-test-auditor",
                   generate_event[:actor]
    end

    test "generated event identifies effective roles" do
      assert_equal ["auditor"],
                   generate_event[:roles]
    end

    test "generated event identifies request" do
      assert_equal "evidence-audit-test",
                   generate_event[:request_id]
    end

    test "generated event records UTC timestamp" do
      assert_equal @time.iso8601(6),
                   generate_event[:timestamp_utc]
    end

    test "generated event identifies CSV export" do
      result = generate_event

      assert_equal "csv", result[:export_type]
      assert_equal "summary", result[:section]
      assert_equal "generated", result[:outcome]
    end

    test "generated event records exact evidence byte count" do
      assert_equal @data.bytesize,
                   generate_event[:bytes]
    end

    test "generated event records exact evidence digest" do
      assert_equal Digest::SHA256.hexdigest(@data),
                   generate_event[:sha256]
    end

    test "generated event excludes evidence contents" do
      generate_event

      refute_includes @output.string,
                      "confidential-test-value"
    end

    test "generated event is logged at information severity" do
      generate_event

      severity, payload = logged_event

      assert_equal "INFO", severity
      assert_equal "generated", payload.fetch("outcome")
    end

    test "logged JSON matches generated audit metadata" do
      result = generate_event

      _, payload = logged_event

      assert_equal result.stringify_keys, payload
    end

    test "archive audit supports binary evidence bytes" do
      data = "\x1F\x8B\x00\xFF".b

      result = @audit.generated(
        export_type: "evidence_bundle",
        data: data
      )

      assert_equal "evidence_bundle", result[:export_type]
      assert_nil result[:section]
      assert_equal data.bytesize, result[:bytes]
      assert_equal Digest::SHA256.hexdigest(data),
                   result[:sha256]
    end

    test "multibyte evidence uses byte count not character count" do
      data = "Révision de conformité"

      result = @audit.generated(
        export_type: "csv",
        section: "summary",
        data: data
      )

      assert_equal data.bytesize, result[:bytes]
      assert_operator result[:bytes], :>, data.length
    end

    test "multiple effective roles are deduplicated and sorted" do
      audit = build_audit(
        roles: [
          :infrastructure_admin,
          :auditor,
          :auditor
        ]
      )

      result = audit.generated(
        export_type: "csv",
        section: "summary",
        data: @data
      )

      assert_equal %w[auditor infrastructure_admin],
                   result[:roles]
    end

    test "unknown roles are excluded" do
      audit = build_audit(
        roles: [:auditor, :unknown_role]
      )

      result = audit.generated(
        export_type: "csv",
        section: "summary",
        data: @data
      )

      assert_equal ["auditor"], result[:roles]
    end

    test "nil roles produce an empty audit role array" do
      audit = build_audit(roles: nil)

      result = audit.generated(
        export_type: "csv",
        section: "summary",
        data: @data
      )

      assert_equal [], result[:roles]
    end

    test "rejected event records rejection outcome" do
      result = reject_event

      assert_equal "rejected", result[:outcome]
      assert_equal "unsupported_export_section",
                   result[:reason]
    end

    test "rejected event excludes arbitrary section contents" do
      reject_event

      _, payload = logged_event

      assert_equal "invalid", payload.fetch("section")

      refute_includes @output.string,
                      "sensitive-invalid-section"
    end

    test "rejected event does not claim evidence generation" do
      result = reject_event

      refute result.key?(:bytes)
      refute result.key?(:sha256)
    end

    test "rejected event uses warning severity" do
      reject_event

      severity, = logged_event

      assert_equal "WARN", severity
    end

    test "failed event identifies exception class" do
      result = fail_event

      assert_equal "failed", result[:outcome]
      assert_equal "RuntimeError", result[:error_class]
    end

    test "failed event excludes exception message" do
      fail_event

      refute_includes @output.string,
                      "sensitive-exception-message"
    end

    test "failed event does not claim generated evidence" do
      result = fail_event

      refute result.key?(:bytes)
      refute result.key?(:sha256)
    end

    test "failed event uses error severity" do
      fail_event

      severity, = logged_event

      assert_equal "ERROR", severity
    end

    test "unsupported export type is rejected" do
      assert_raises ArgumentError do
        @audit.generated(
          export_type: "unsupported",
          data: @data
        )
      end

      assert_empty @output.string
    end

    test "actor newline cannot create a separate log entry" do
      audit = build_audit(
        actor: "auditor\nforged-log-entry"
      )

      audit.generated(
        export_type: "csv",
        section: "summary",
        data: @data
      )

      assert_equal 1, @output.string.lines.length

      _, payload = logged_event

      assert_equal "auditor\nforged-log-entry",
                   payload.fetch("actor")
    end

    test "request identifier newline is JSON encoded" do
      audit = build_audit(
        request_id: "request\nforged-entry"
      )

      audit.generated(
        export_type: "csv",
        section: "summary",
        data: @data
      )

      assert_equal 1, @output.string.lines.length

      _, payload = logged_event

      assert_equal "request\nforged-entry",
                   payload.fetch("request_id")
    end

    private

    def build_audit(**overrides)
      Audit.new(
        **{
          actor: "herga-test-auditor",
          roles: [:auditor],
          request_id: "evidence-audit-test",
          logger: @logger,
          clock: -> { @time }
        }.merge(overrides)
      )
    end

    def generate_event
      @audit.generated(
        export_type: "csv",
        section: "summary",
        data: @data
      )
    end

    def reject_event
      @audit.rejected(
        export_type: "csv",
        section: "sensitive-invalid-section",
        reason: "unsupported_export_section"
      )
    end

    def fail_event
      @audit.failed(
        export_type: "csv",
        section: "summary",
        error: RuntimeError.new(
          "sensitive-exception-message"
        )
      )
    end

    def logged_event
      severity, message = @output.string.strip.split("|", 2)

      [severity, JSON.parse(message)]
    end
  end
end