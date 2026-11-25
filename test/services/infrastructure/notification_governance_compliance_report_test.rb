# frozen_string_literal: true

require "test_helper"
require "csv"
require "securerandom"

module Infrastructure
  class NotificationGovernanceComplianceReportTest <
    ActiveSupport::TestCase

    Report = NotificationGovernanceComplianceReport

    setup do
      @reference = "CSV-#{SecureRandom.hex(8)}"

      @notification = InfrastructureNotification.create!(
        event_key: "csv-security-#{SecureRandom.hex(12)}",
        event_type: "IncidentOpened",
        source_type: "InfrastructureIncident",
        source_id: 1,
        recipient: "confidential-recipient@example.invalid",
        occurred_at: Time.current,
        status: "Pending"
      )

      @policy = NotificationRetentionPolicy.create!(
        reference: @reference,
        name: "=1+1",
        retention_days: 365,
        status: "Draft",
        version: 1
      )

      @policy_event = NotificationRetentionEvent.create!(
        notification_retention_policy: @policy,
        action: "Created",
        actor: "+123",
        to_status: "Draft",
        policy_version: 1
      )

      @hold = NotificationLegalHold.create!(
        infrastructure_notification: @notification,
        reference: "HOLD-#{@reference}",
        reason: "@SUM(A1:A5)",
        placed_by: "independent-creator",
        placed_at: Time.current
      )

      @hold_event = NotificationLegalHoldEvent.create!(
        notification_legal_hold: @hold,
        action: "Placed",
        actor: "independent-creator",
        justification: "Legal hold placed for evidence security testing"
      )

      @report = Report.new
    end

    # ==========================================================
    # SECTION A - EXPLICIT FIELD ALLOWLISTS
    # ==========================================================

    test "summary exports only approved fields" do
      assert_equal %w[
        metric value assessed_at
      ], rows("summary").headers
    end

    test "policy export contains only approved fields" do
      assert_equal %w[
        id reference name status retention_days version
        approved_by approved_at suspended_by suspended_at
        created_at
      ], rows("policies").headers
    end

    test "policy event export contains only approved fields" do
      assert_equal %w[
        id policy_id action actor from_status to_status
        policy_version created_at
      ], rows("policy_events").headers
    end

    test "legal hold export contains only approved fields" do
      assert_equal %w[
        id notification_id reference reason placed_by
        placed_at released_by released_at
      ], rows("legal_holds").headers
    end

    test "legal hold event export contains only approved fields" do
      assert_equal %w[
        id legal_hold_id action actor justification created_at
      ], rows("legal_hold_events").headers
    end

    # ==========================================================
    # SECTION B - FORMULA INJECTION PROTECTION
    # ==========================================================

    test "policy name is neutralised in exported evidence" do
      row = find_row("policies", @policy.id)

      assert_equal "'=1+1", row["name"]
    end

    test "policy reference is neutralised in exported evidence" do
      @policy.update_columns(reference: "+123")

      row = find_row("policies", @policy.id)

      assert_equal "'+123", row["reference"]
    end

    test "policy event actor is neutralised" do
      row = find_row("policy_events", @policy_event.id)

      assert_equal "'+123", row["actor"]
    end

    test "legal hold reason is neutralised" do
      row = find_row("legal_holds", @hold.id)

      assert_equal "'@SUM(A1:A5)", row["reason"]
    end

    test "legal hold reference is neutralised" do
      @hold.update_columns(reference: "-123")

      row = find_row("legal_holds", @hold.id)

      assert_equal "'-123", row["reference"]
    end

    test "unicode formula prefix is neutralised" do
      @policy.update_columns(name: "＝1+1")

      row = find_row("policies", @policy.id)

      assert_equal "'＝1+1", row["name"]
    end

    test "whitespace prefixed formula is neutralised" do
      @hold.update_columns(reason: " \t=1+1")

      row = find_row("legal_holds", @hold.id)

      assert_equal "' \t=1+1", row["reason"]
    end

    test "legal hold release justification is neutralised" do
      event = NotificationLegalHoldEvent.create!(
        notification_legal_hold: @hold,
        action: "Released",
        actor: "independent-reviewer",
        justification: "=1+1"
      )

      row = find_row("legal_hold_events", event.id)

      assert_equal "'=1+1", row["justification"]
    end

    # ==========================================================
    # SECTION C - CONFIDENTIALITY
    # ==========================================================

    test "all governance sections exclude notification recipient" do
      Report::SECTIONS.each do |section|
        data = @report.csv(section: section)

        refute_includes data, @notification.recipient
      end
    end

    test "all governance sections exclude notification event key" do
      Report::SECTIONS.each do |section|
        data = @report.csv(section: section)

        refute_includes data, @notification.event_key
      end
    end

    test "all governance sections exclude delivery detail columns" do
      prohibited_headers = %w[
        recipient
        password
        credentials
        access_token
        refresh_token
        error_message
        last_error
        signing_key
        private_key
      ]

      Report::SECTIONS.each do |section|
        headers = rows(section).headers

        assert_empty headers & prohibited_headers
      end
    end

    # ==========================================================
    # SECTION D - ORIGINAL DATA PRESERVATION
    # ==========================================================

    test "policy export does not modify original policy" do
      before = @policy.attributes

      @report.csv(section: "policies")

      assert_equal before, @policy.reload.attributes
      assert_equal "=1+1", @policy.name
    end

    test "policy event export preserves original audit actor" do
      before = @policy_event.attributes

      @report.csv(section: "policy_events")

      assert_equal before, @policy_event.reload.attributes
      assert_equal "+123", @policy_event.actor
    end

    test "legal hold export preserves original reason" do
      before = @hold.attributes

      @report.csv(section: "legal_holds")

      assert_equal before, @hold.reload.attributes
      assert_equal "@SUM(A1:A5)", @hold.reason
    end

    test "legal hold event export preserves original audit event" do
      before = @hold_event.attributes

      @report.csv(section: "legal_hold_events")

      assert_equal before, @hold_event.reload.attributes
    end

    test "all exports preserve notification record" do
      before = @notification.attributes

      Report::SECTIONS.each do |section|
        @report.csv(section: section)
      end

      assert_equal before, @notification.reload.attributes
    end

    # ==========================================================
    # SECTION E - CSV DATA INTEGRITY
    # ==========================================================

    test "ordinary policy name is preserved" do
      @policy.update_columns(
        name: "HERGA Notification Retention Policy"
      )

      row = find_row("policies", @policy.id)

      assert_equal @policy.name, row["name"]
    end

    test "commas and quotes survive CSV serialisation" do
      value = 'Legal review, including "supporting evidence"'

      @hold.update_columns(reason: value)

      row = find_row("legal_holds", @hold.id)

      assert_equal value, row["reason"]
    end

    test "multiline legal hold reason is preserved" do
      value = "First paragraph\nSecond paragraph"

      @hold.update_columns(reason: value)

      row = find_row("legal_holds", @hold.id)

      assert_equal value, row["reason"]
    end

    test "retention days and version remain accurate" do
      row = find_row("policies", @policy.id)

      assert_equal "365", row["retention_days"]
      assert_equal "1", row["version"]
    end

    test "unsupported evidence section raises argument error" do
      assert_raises ArgumentError do
        @report.csv(section: "unsupported")
      end
    end

    test "all supported sections generate parseable CSV" do
      Report::SECTIONS.each do |section|
        assert_kind_of CSV::Table, rows(section)
      end
    end

    private

    def rows(section)
      CSV.parse(
        @report.csv(section: section),
        headers: true
      )
    end

    def find_row(section, id)
      row = rows(section).find do |record|
        record["id"] == id.to_s
      end

      assert_not_nil row,
                     "Expected record #{id} in #{section}"

      row
    end
  end
end