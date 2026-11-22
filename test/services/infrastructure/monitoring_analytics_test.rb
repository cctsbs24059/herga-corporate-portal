# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class MonitoringAnalyticsTest < ActiveSupport::TestCase
    test "defaults to thirty days and returns one row per UTC date" do
      now = Time.utc(2026, 11, 21, 12)
      report = MonitoringAnalytics.new(params: {}, now: now).call
      assert_equal "30", report.period
      assert_equal 31, report.daily.length
      assert_equal Date.new(2026, 11, 21), report.daily.last[:date]
    end

    test "rejects unsupported periods" do
      report = MonitoringAnalytics.new(params: { period: "999" }, now: Time.utc(2026, 11, 21)).call
      assert_equal "30", report.period
    end

    test "empty denominators produce nil percentages rather than false zero availability" do
      report = MonitoringAnalytics.new(params: { period: "7" }, now: Time.utc(2020, 1, 1)).call
      assert_nil report.summary[:execution_success_percentage]
      assert_nil report.summary[:connectivity_availability_percentage]
      assert_equal 0, report.summary[:breaches]
    end
  end
end
