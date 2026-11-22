# frozen_string_literal: true

require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationAnalyticsTest < ActiveSupport::TestCase
    NOW = Time.utc(2035, 6, 15, 12, 0, 0)

    setup do
      @token = SecureRandom.hex(8)
    end

    test "empty reporting period has zero totals and no duration" do
      report = analytics
      assert_equal 0, report[:total]
      assert_equal InfrastructureNotification::STATUSES.index_with { 0 }, report[:statuses]
      assert_equal 0.0, report[:accepted_percentage]
      assert_equal 0.0, report[:unknown_percentage]
      assert_equal 0, report[:attempts][:total]
      assert_nil report[:average_processing_seconds]
      assert_empty report[:daily]
    end

    test "status totals and percentages reflect current statuses" do
      create_notification(status: "Accepted", created_at: NOW - 1.hour)
      create_notification(status: "Accepted", created_at: NOW - 2.hours)
      create_notification(status: "Unknown", created_at: NOW - 3.hours)
      create_notification(status: "Pending", created_at: NOW - 4.hours)

      report = analytics(period: "24h")
      assert_equal 4, report[:total]
      assert_equal({ "Pending" => 1, "Sending" => 0, "Accepted" => 2, "Unknown" => 1 }, report[:statuses])
      assert_equal 50.0, report[:accepted_percentage]
      assert_equal 25.0, report[:unknown_percentage]
    end

    test "event breakdown counts only notifications in period" do
      create_notification(event_type: "IncidentOpened", created_at: NOW - 1.hour)
      create_notification(event_type: "IncidentOpened", created_at: NOW - 2.hours)
      create_notification(event_type: "IncidentRecovered", created_at: NOW - 3.hours)
      create_notification(event_type: "IncidentOpened", created_at: NOW - 8.days)

      report = analytics(period: "7d")
      assert_equal 2, report[:events]["IncidentOpened"]
      assert_equal 1, report[:events]["IncidentRecovered"]
      assert_equal 0, report[:events]["AvailabilityBreached"]
      assert_equal InfrastructureNotification::EVENTS.sort, report[:events].keys.sort
    end

    test "period boundaries include exact start and end and exclude outside records" do
      create_notification(created_at: NOW - 24.hours)
      create_notification(created_at: NOW)
      create_notification(created_at: NOW - 24.hours - 1.second)
      create_notification(created_at: NOW + 1.second)

      report = analytics(period: "24h")
      assert_equal 2, report[:total]
      assert_equal NOW - 24.hours, report[:since]
      assert_equal NOW, report[:until_at]
    end

    test "all four reporting periods apply their respective cutoffs" do
      create_notification(created_at: NOW - 12.hours)
      create_notification(created_at: NOW - 3.days)
      create_notification(created_at: NOW - 20.days)
      create_notification(created_at: NOW - 60.days)
      create_notification(created_at: NOW - 100.days)

      assert_equal 1, analytics(period: "24h")[:total]
      assert_equal 2, analytics(period: "7d")[:total]
      assert_equal 3, analytics(period: "30d")[:total]
      assert_equal 4, analytics(period: "90d")[:total]
    end

    test "invalid period falls back to seven days" do
      create_notification(created_at: NOW - 3.days)
      create_notification(created_at: NOW - 20.days)
      report = analytics(period: "invalid")
      assert_equal "7d", report[:period]
      assert_equal 1, report[:total]
    end

    test "attempt counts use attempted at rather than notification creation" do
      notification = create_notification(status: "Accepted", created_at: NOW - 20.days)
      create_attempt(notification, status: "Accepted", attempted_at: NOW - 1.hour)
      create_attempt(notification, status: "Unknown", attempted_at: NOW - 2.hours)
      create_attempt(notification, status: "Accepted", attempted_at: NOW - 10.days)

      report = analytics(period: "24h")
      assert_equal 0, report[:total]
      assert_equal({ total: 2, accepted: 1, unknown: 1 }, report[:attempts])
    end

    test "average processing interval excludes missing and reversed timestamps" do
      create_notification(status: "Accepted", created_at: NOW - 1.hour,
                          attempted_at: NOW - 50.seconds, accepted_at: NOW - 40.seconds)
      create_notification(status: "Accepted", created_at: NOW - 1.hour,
                          attempted_at: NOW - 35.seconds, accepted_at: NOW - 5.seconds)
      create_notification(status: "Accepted", created_at: NOW - 1.hour,
                          attempted_at: nil, accepted_at: NOW - 1.second)
      create_notification(status: "Accepted", created_at: NOW - 1.hour,
                          attempted_at: NOW - 1.second, accepted_at: NOW - 10.seconds)
      create_notification(status: "Unknown", created_at: NOW - 1.hour,
                          attempted_at: NOW - 50.seconds, accepted_at: NOW)

      assert_equal 20.0, analytics(period: "24h")[:average_processing_seconds]
    end

    test "daily activity uses UTC dates and zero fills missing statuses" do
      create_notification(status: "Accepted", created_at: Time.utc(2035, 6, 14, 23, 59, 59))
      create_notification(status: "Unknown", created_at: Time.utc(2035, 6, 15, 0, 0, 1))

      report = analytics(period: "24h")
      assert_equal %w[2035-06-14 2035-06-15], report[:daily].keys
      assert_equal 1, report[:daily]["2035-06-14"]["Accepted"]
      assert_equal 0, report[:daily]["2035-06-14"]["Unknown"]
      assert_equal 1, report[:daily]["2035-06-15"]["Unknown"]
      assert_equal 0, report[:daily]["2035-06-15"]["Pending"]
    end

    test "analytics is read only" do
      notification = create_notification(status: "Pending", created_at: NOW - 1.hour)
      original = notification.attributes
      assert_no_difference -> { InfrastructureNotification.count } do
        assert_no_difference -> { InfrastructureNotificationAttempt.count } do
          analytics(period: "24h")
        end
      end
      assert_equal original, notification.reload.attributes
    end

    private

    def analytics(period: "7d")
      Infrastructure::NotificationAnalytics.new(period: period, now: NOW).call
    end

    def create_notification(status: "Pending", event_type: "IncidentOpened", created_at: NOW - 1.hour,
                            attempted_at: nil, accepted_at: nil)
      InfrastructureNotification.create!(
        event_key: "analytics-test-#{@token}-#{SecureRandom.hex(10)}",
        event_type: event_type,
        source_type: "InfrastructureIncident",
        source_id: 1,
        recipient: "analytics-test@example.com",
        occurred_at: created_at,
        status: status,
        attempted_at: attempted_at,
        accepted_at: accepted_at,
        created_at: created_at,
        updated_at: created_at
      )
    end

    def create_attempt(notification, status:, attempted_at:)
      InfrastructureNotificationAttempt.create!(
        infrastructure_notification: notification,
        status: status,
        attempted_at: attempted_at
      )
    end
  end
end
