# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class NotificationRetentionGovernanceTest < ActiveSupport::TestCase
    test "defaults to draft and never permits disposal" do
      result = NotificationRetentionGovernance.new(settings: {}).call
      assert_equal "Draft", result[:policy_status]
      assert_equal 365, result[:retention_days]
      assert_not result[:disposal_authorized]
      assert result[:read_only]
    end

    test "approval requires all metadata" do
      result = NotificationRetentionGovernance.new(settings: {
        "HERGA_NOTIFICATION_RETENTION_POLICY_STATUS" => "Approved"
      }).call
      assert_equal "Draft", result[:policy_status]
      assert_not result[:metadata_complete]
    end

    test "complete approval metadata is informational only" do
      result = NotificationRetentionGovernance.new(settings: {
        "HERGA_NOTIFICATION_RETENTION_POLICY_STATUS" => "Approved",
        "HERGA_NOTIFICATION_RETENTION_POLICY_REFERENCE" => "POL-001",
        "HERGA_NOTIFICATION_RETENTION_APPROVED_BY" => "Records Management",
        "HERGA_NOTIFICATION_RETENTION_APPROVED_ON" => "2026-11-23",
        "HERGA_NOTIFICATION_RETENTION_DAYS" => "730"
      }).call
      assert_equal "Approved", result[:policy_status]
      assert_equal 730, result[:retention_days]
      assert_not result[:disposal_authorized]
    end

    test "invalid dates and periods fail safely" do
      result = NotificationRetentionGovernance.new(settings: {
        "HERGA_NOTIFICATION_RETENTION_POLICY_STATUS" => "Approved",
        "HERGA_NOTIFICATION_RETENTION_POLICY_REFERENCE" => "POL-001",
        "HERGA_NOTIFICATION_RETENTION_APPROVED_BY" => "Records Management",
        "HERGA_NOTIFICATION_RETENTION_APPROVED_ON" => "invalid",
        "HERGA_NOTIFICATION_RETENTION_DAYS" => "12"
      }).call
      assert_equal "Draft", result[:policy_status]
      assert_equal 365, result[:retention_days]
    end

    test "suspended policy remains non-disposable" do
      result = NotificationRetentionGovernance.new(settings: {
        "HERGA_NOTIFICATION_RETENTION_POLICY_STATUS" => "Suspended"
      }).call
      assert_equal "Suspended", result[:policy_status]
      assert_not result[:disposal_authorized]
    end
  end
end
