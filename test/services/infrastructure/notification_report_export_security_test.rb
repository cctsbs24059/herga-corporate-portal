# frozen_string_literal: true

require "test_helper"
require "csv"
require "securerandom"

module Infrastructure
  class NotificationReportExportSecurityTest <
    ActiveSupport::TestCase

    Export = NotificationReportExport

    setup do
      @notification = InfrastructureNotification.create!(
        event_key: "report-security-#{SecureRandom.hex(12)}",
        event_type: "IncidentOpened",
        source_type: "InfrastructureIncident",
        source_id: 1,
        recipient: "confidential-report-recipient@example.invalid",
        occurred_at: Time.current,
        status: "Pending"
      )
    end

    test "history export excludes notification recipient" do
      data = export("history")

      refute_includes data, @notification.recipient
    end

    test "history export excludes internal event key" do
      data = export("history")

      refute_includes data, @notification.event_key
    end

    test "history export contains only approved columns" do
      assert_equal %w[
        notification_id
        event_type
        status
        source_type
        source_id
        escalation_level
        attempt_count
        occurred_at_utc
        created_at_utc
        attempted_at_utc
        accepted_at_utc
      ], rows("history").headers
    end

    test "attempt export contains only approved columns" do
      assert_equal %w[
        attempt_id
        notification_id
        event_type
        status
        attempted_at_utc
      ], rows("attempts").headers
    end

    test "analytics export contains only approved columns" do
      assert_equal %w[
        metric
        category
        count
        percentage
      ], rows("analytics").headers
    end

    test "all operational exports exclude sensitive column names" do
      prohibited = %w[
        recipient
        error
        error_message
        last_error
        password
        credentials
        access_token
        refresh_token
        event_key
      ]

      Export::TYPES.each do |type|
        assert_empty rows(type).headers & prohibited
      end
    end

    test "all operational exports exclude notification recipient" do
      Export::TYPES.each do |type|
        refute_includes export(type), @notification.recipient
      end
    end

    test "history export neutralises formula in source type" do
      @notification.update_columns(
        source_type: "=1+1"
      )

      row = notification_row

      assert_equal "'=1+1", row["source_type"]
    end

    test "history export neutralises unicode formula prefix" do
      @notification.update_columns(
        source_type: "＝1+1"
      )

      row = notification_row

      assert_equal "'＝1+1", row["source_type"]
    end

    test "history export neutralises leading control character" do
      @notification.update_columns(
        source_type: "\t+123"
      )

      row = notification_row

      assert_equal "'\t+123", row["source_type"]
    end

    test "history export preserves ordinary source type" do
      row = notification_row

      assert_equal "InfrastructureIncident",
                   row["source_type"]
    end

    test "history export preserves numeric source identifier" do
      row = notification_row

      assert_equal "1", row["source_id"]
    end

    test "sanitisation does not modify original notification" do
      @notification.update_columns(
        source_type: "=1+1"
      )

      before = @notification.reload.attributes

      export("history")

      assert_equal before, @notification.reload.attributes

      assert_equal "=1+1", @notification.source_type
    end

    test "all operational exports preserve original record" do
      before = @notification.attributes

      Export::TYPES.each do |type|
        export(type)
      end

      assert_equal before, @notification.reload.attributes
    end

    private

    def export(type)
      Export.new(
        period: "7d",
        type: type
      ).csv
    end

    def rows(type)
      CSV.parse(
        export(type),
        headers: true
      )
    end

    def notification_row
      row = rows("history").find do |record|
        record["notification_id"] == @notification.id.to_s
      end

      assert_not_nil row

      row
    end
  end
end