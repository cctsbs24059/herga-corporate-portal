# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "stringio"
require "json"
require "csv"
require "digest"
require "zlib"
require "rubygems/package"
require "logger"

class NotificationGovernanceEvidenceAccountabilityTest <
  ActionDispatch::IntegrationTest

  include Devise::Test::IntegrationHelpers

  Audit = Infrastructure::NotificationGovernanceEvidenceAudit

  Report =
    Infrastructure::NotificationGovernanceComplianceReport

  Bundle =
    Infrastructure::NotificationGovernanceEvidenceBundle

  setup do
    @user = User.create!(
      username: "evidence-accountability-#{SecureRandom.hex(8)}",
      admin: false
    )

    @policy = Infrastructure::NotificationRetentionPolicy.create!(
      reference: "ACCOUNTABILITY-#{SecureRandom.hex(8)}",
      name: "=1+1",
      retention_days: 365,
      status: "Draft",
      version: 1
    )

    @notification = InfrastructureNotification.create!(
      event_key: "accountability-#{SecureRandom.hex(12)}",
      event_type: "IncidentOpened",
      source_type: "InfrastructureIncident",
      source_id: 1,
      recipient: "private-recipient@example.invalid",
      occurred_at: Time.current,
      status: "Pending"
    )

    @hold = Infrastructure::NotificationLegalHold.create!(
      infrastructure_notification: @notification,
      reference: "HOLD-#{SecureRandom.hex(8)}",
      reason: "@SUM(A1:A5)",
      placed_by: "independent-creator",
      placed_at: Time.current
    )

    @output = StringIO.new
    @logger = Logger.new(@output)

    @logger.formatter = proc do |_severity, _time, _name, message|
      "#{message}\n"
    end
  end

  teardown do
    sign_out @user
  end

  # ==========================================================
  # SECTION A - CSV AUDIT ACCOUNTABILITY
  # ==========================================================

  Report::SECTIONS.each do |section|

    test "#{section} export generates exactly one audit event" do
      as_roles([:auditor]) do
        get csv_path(section)

        assert_response :success

        event = single_event

        assert_equal "governance_evidence_export",
                     event.fetch("event")

        assert_equal "generated", event.fetch("outcome")
        assert_equal "csv", event.fetch("export_type")
        assert_equal section, event.fetch("section")
      end
    end

    test "#{section} audit digest matches actual response" do
      as_roles([:auditor]) do
        get csv_path(section)

        assert_response :success

        event = single_event

        assert_equal Digest::SHA256.hexdigest(response.body),
                     event.fetch("sha256")

        assert_equal response.body.bytesize,
                     event.fetch("bytes")
      end
    end

  end

  test "CSV audit identifies authenticated actor" do
    as_roles([:auditor]) do
      get csv_path("policies")

      assert_response :success

      assert_equal @user.username,
                   single_event.fetch("actor")
    end
  end

  test "CSV audit identifies verified effective roles" do
    as_roles([:infrastructure_admin, :auditor]) do
      get csv_path("policies")

      assert_response :success

      assert_equal %w[auditor infrastructure_admin],
                   single_event.fetch("roles")
    end
  end

  test "CSV audit request identifier matches response" do
    as_roles([:auditor]) do
      get csv_path("summary")

      assert_response :success

      assert_equal response.headers["X-Request-Id"],
                   single_event.fetch("request_id")
    end
  end

  test "CSV audit timestamp is UTC" do
    as_roles([:auditor]) do
      get csv_path("summary")

      assert_response :success

      timestamp = single_event.fetch("timestamp_utc")

      assert_match(/Z\z/, timestamp)
      assert_kind_of Time, Time.iso8601(timestamp)
    end
  end

  test "CSV audit excludes actual policy contents" do
    as_roles([:auditor]) do
      get csv_path("policies")

      assert_response :success

      assert_includes response.body, @policy.reference

      refute_includes @output.string, @policy.reference
      refute_includes @output.string, @policy.name
    end
  end

  test "CSV audit excludes legal hold reason" do
    as_roles([:auditor]) do
      get csv_path("legal_holds")

      assert_response :success

      assert_includes response.body, @hold.reference

      refute_includes @output.string, @hold.reference
      refute_includes @output.string, @hold.reason
    end
  end

  # ==========================================================
  # SECTION B - ARCHIVE AUDIT ACCOUNTABILITY
  # ==========================================================

  test "archive download generates exactly one audit event" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      event = single_event

      assert_equal "evidence_bundle",
                   event.fetch("export_type")

      assert_equal "generated", event.fetch("outcome")
      assert_nil event.fetch("section")
    end
  end

  test "archive audit digest matches downloaded bytes" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      event = single_event

      assert_equal Digest::SHA256.hexdigest(response.body),
                   event.fetch("sha256")

      assert_equal response.body.bytesize,
                   event.fetch("bytes")
    end
  end

  test "archive audit identifies actor roles and request" do
    as_roles([:security_admin]) do
      get bundle_path

      assert_response :success

      event = single_event

      assert_equal @user.username, event.fetch("actor")
      assert_equal ["security_admin"], event.fetch("roles")

      assert_equal response.headers["X-Request-Id"],
                   event.fetch("request_id")
    end
  end

  test "archive audit excludes confidential record contents" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      single_event

      refute_includes @output.string, @policy.reference
      refute_includes @output.string, @hold.reference
      refute_includes @output.string, @notification.recipient
    end
  end

  # ==========================================================
  # SECTION C - REJECTED AND FAILED EXPORTS
  # ==========================================================

  test "invalid section produces rejected audit event" do
    as_roles([:auditor]) do
      get csv_path("confidential-invalid-section")

      assert_response :bad_request

      event = single_event

      assert_equal "rejected", event.fetch("outcome")
      assert_equal "invalid", event.fetch("section")

      assert_equal "unsupported_export_section",
                   event.fetch("reason")

      refute event.key?("sha256")
      refute event.key?("bytes")

      refute_includes @output.string,
                      "confidential-invalid-section"
    end
  end

  test "oversized archive produces failed audit event" do
    as_roles([:auditor]) do
      failing_constructor = lambda do |*args, **kwargs|
        raise Bundle::BundleTooLarge,
              "confidential-internal-error"
      end

      Bundle.stub(:new, failing_constructor) do
        get bundle_path

        assert_response :unprocessable_entity
      end

      event = single_event

      assert_equal "failed", event.fetch("outcome")

      assert_equal Bundle::BundleTooLarge.name,
                   event.fetch("error_class")

      refute event.key?("sha256")
      refute event.key?("bytes")

      refute_includes @output.string,
                      "confidential-internal-error"

      refute_includes response.body,
                      "confidential-internal-error"
    end
  end

  test "denied CSV request produces no generated audit event" do
    as_roles([:employee]) do
      get csv_path("policies")

      assert_redirected_to root_path

      assert_empty audit_events
    end
  end

  test "denied archive request produces no generated audit event" do
    as_roles([:infrastructure_admin]) do
      get bundle_path

      assert_redirected_to root_path

      assert_empty audit_events
    end
  end

  test "directory failure produces no generated audit event" do
    as_roles(nil) do
      get bundle_path

      assert_redirected_to new_user_session_path

      assert_empty audit_events
    end
  end

  # ==========================================================
  # SECTION D - DOWNLOADED EVIDENCE CONFIDENTIALITY
  # ==========================================================

  test "downloaded policy CSV neutralises formula injection" do
    as_roles([:auditor]) do
      get csv_path("policies")

      assert_response :success

      row = find_csv_record(response.body, @policy.id)

      assert_equal "'=1+1", row["name"]
    end
  end

  test "downloaded legal hold CSV neutralises formula injection" do
    as_roles([:auditor]) do
      get csv_path("legal_holds")

      assert_response :success

      row = find_csv_record(response.body, @hold.id)

      assert_equal "'@SUM(A1:A5)", row["reason"]
    end
  end

  test "downloaded archive contains neutralised policy name" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      files = archive_files(response.body)

      row = find_csv_record(
        files.fetch("policies.csv"),
        @policy.id
      )

      assert_equal "'=1+1", row["name"]
    end
  end

  test "downloaded archive contains neutralised legal hold reason" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      files = archive_files(response.body)

      row = find_csv_record(
        files.fetch("legal_holds.csv"),
        @hold.id
      )

      assert_equal "'@SUM(A1:A5)", row["reason"]
    end
  end

  test "downloaded archive excludes notification recipient" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      files = archive_files(response.body)

      files.each do |name, contents|
        next unless name.end_with?(".csv")

        refute_includes contents, @notification.recipient
      end
    end
  end

  test "archive verification succeeds after CSV sanitisation" do
    as_roles([:auditor]) do
      get bundle_path

      assert_response :success

      manifest = Bundle.verify(response.body)

      assert_equal Report::SECTIONS,
                   manifest.fetch("sections").map { |section|
                     section.fetch("section")
                   }
    end
  end

  test "populated evidence records remain unchanged after downloads" do
    as_roles([:auditor]) do
      before_policy = @policy.attributes
      before_hold = @hold.attributes
      before_notification = @notification.attributes

      get csv_path("policies")
      assert_response :success

      get csv_path("legal_holds")
      assert_response :success

      get bundle_path
      assert_response :success

      assert_equal before_policy, @policy.reload.attributes
      assert_equal before_hold, @hold.reload.attributes

      assert_equal before_notification,
                   @notification.reload.attributes
    end
  end

  # ==========================================================
  # TEST HELPERS
  # ==========================================================

  private

  def as_roles(roles)
    sign_in @user

    original_constructor = Audit.method(:new)
    logger = @logger

    audit_constructor = lambda do |**options|
      original_constructor.call(
        **options.merge(logger: logger)
      )
    end

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      roles
    ) do
      Audit.stub(:new, audit_constructor) do
        yield
      end
    end
  end

  def csv_path(section)
    infrastructure_notification_governance_compliance_export_path(
      section: section
    )
  end

  def bundle_path
    infrastructure_notification_governance_evidence_bundle_path
  end

  def audit_events
    @output.string.lines
      .reject { |line| line.strip.empty? }
      .map { |line| JSON.parse(line) }
  end

  def single_event
    events = audit_events

    assert_equal 1, events.length

    events.first
  end

  def find_csv_record(data, id)
    row = CSV.parse(data, headers: true).find do |record|
      record["id"] == id.to_s
    end

    assert_not_nil row

    row
  end

  def archive_files(data)
    files = {}

    Zlib::GzipReader.wrap(StringIO.new(data)) do |gzip|
      Gem::Package::TarReader.new(gzip) do |tar|
        tar.each do |entry|
          next unless entry.file?

          files[entry.full_name] = entry.read
        end
      end
    end

    files
  end
end