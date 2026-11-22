# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "csv"

module Infrastructure
  class NotificationReportExportTest < ActiveSupport::TestCase
    setup do
      @now = Time.utc(2035, 1, 15, 12)
    end

    test "defaults invalid selections to seven day history" do
      report = NotificationReportExport.new(period: "invalid", type: "bad", status: "bad", event_type: "bad", now: @now)
      assert_equal "7d", report.period
      assert_equal "history", report.type
      assert_equal "", report.status
      assert_equal "", report.event_type
    end

    test "empty history contains only expected headers" do
      rows = CSV.parse(NotificationReportExport.new(period: "24h", now: @now).csv)
      assert_equal 1, rows.length
      assert_includes rows.first, "notification_id"
      refute_includes rows.first, "recipient"
      refute_includes rows.first, "last_error"
    end

    test "history applies status and event filters" do
      create_notification(status: "Accepted", event_type: "IncidentOpened")
      create_notification(status: "Unknown", event_type: "IncidentRecovered")
      report = NotificationReportExport.new(period: "7d", status: "Accepted", event_type: "IncidentOpened", now: @now)
      rows = CSV.parse(report.csv, headers: true)
      assert_equal 1, rows.length
      assert_equal "Accepted", rows.first["status"]
      assert_equal "IncidentOpened", rows.first["event_type"]
    end

    test "history includes exact period boundary but excludes earlier records" do
      create_notification(status: "Pending", created_at: @now - 7.days)
      create_notification(status: "Pending", created_at: @now - 7.days - 1.second)
      report = NotificationReportExport.new(period: "7d", now: @now)
      assert_equal 1, CSV.parse(report.csv, headers: true).length
    end

    test "attempt export uses attempt timestamp rather than notification creation timestamp" do
      notification = create_notification(status: "Accepted", created_at: @now - 40.days)
      InfrastructureNotificationAttempt.create!(infrastructure_notification: notification, status: "Accepted", attempted_at: @now - 1.hour)
      report = NotificationReportExport.new(type: "attempts", period: "24h", now: @now)
      rows = CSV.parse(report.csv, headers: true)
      assert_equal 1, rows.length
      assert_equal notification.id.to_s, rows.first["notification_id"]
      refute_includes rows.headers, "error_message"
    end

    test "analytics uses filtered notification population" do
      create_notification(status: "Accepted", event_type: "IncidentOpened")
      create_notification(status: "Unknown", event_type: "IncidentRecovered")
      report = NotificationReportExport.new(type: "analytics", status: "Accepted", now: @now)
      rows = CSV.parse(report.csv, headers: true)
      total = rows.find { |row| row["metric"] == "Notifications created" }
      accepted = rows.find { |row| row["metric"] == "Current status" && row["category"] == "Accepted" }
      assert_equal "1", total["count"]
      assert_equal "100.0", accepted["percentage"]
    end

    test "csv generation does not modify records" do
      create_notification(status: "Pending")
      assert_no_difference -> { InfrastructureNotification.count } do
        assert_no_difference -> { InfrastructureNotificationAttempt.count } do
          NotificationReportExport.new(now: @now).csv
        end
      end
    end

    private

    def create_notification(status:, event_type: "IncidentOpened", created_at: @now - 1.hour)
      record = InfrastructureNotification.create!(
        event_key: "HERGA-REPORT-TEST-#{SecureRandom.uuid}",
        event_type: event_type,
        source_type: "InfrastructureAsset",
        source_id: 1,
        recipient: "report-test@example.invalid",
        status: status,
        occurred_at: created_at
      )
      record.update_columns(created_at: created_at, updated_at: created_at)
      record
    end
  end
end
