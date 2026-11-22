# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class NotificationRetentionAssessmentTest < ActiveSupport::TestCase
    test "default retention is 365 days" do
      assessment = Infrastructure::NotificationRetentionAssessment.new(retention_days: 365).call
      assert_equal 365, assessment[:retention_days]
      assert assessment[:read_only]
      assert_not assessment[:eligible_for_deletion]
    end

    test "invalid retention falls back to default" do
      assessment = Infrastructure::NotificationRetentionAssessment.new(retention_days: "invalid").call
      assert_equal 365, assessment[:retention_days]
    end

    test "out of range retention falls back to default" do
      [0, 29, 3651].each do |days|
        assessment = Infrastructure::NotificationRetentionAssessment.new(retention_days: days).call
        assert_equal 365, assessment[:retention_days]
      end
    end

    test "cutoff uses supplied assessment time" do
      now = Time.utc(2026, 11, 22, 12)
      assessment = Infrastructure::NotificationRetentionAssessment.new(now: now, retention_days: 90).call
      assert_equal now - 90.days, assessment[:cutoff_at]
    end

    test "assessment never modifies notifications or attempts" do
      service = Infrastructure::NotificationRetentionAssessment.new(retention_days: 365)
      assert_no_difference -> { InfrastructureNotification.count } do
        assert_no_difference -> { InfrastructureNotificationAttempt.count } do
          service.call
        end
      end
    end

    test "protected statuses are counted separately" do
      assessment = Infrastructure::NotificationRetentionAssessment.new(retention_days: 365).call
      assert_equal %w[Pending Sending Unknown].sum { |status| assessment[:protected_by_status].fetch(status, 0) }, assessment[:protected_notifications]
    end
  end
end
