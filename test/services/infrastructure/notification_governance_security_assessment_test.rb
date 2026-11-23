# frozen_string_literal: true
require "test_helper"

module Infrastructure
  class NotificationGovernanceSecurityAssessmentTest < ActiveSupport::TestCase
    test "assessment exposes read only governance indicators" do
      result = NotificationGovernanceSecurityAssessment.new.call
      assert_kind_of Hash, result
      assert_equal false, result[:disposal_enabled]
      assert_kind_of Integer, result[:policy_count]
      assert_kind_of Integer, result[:active_hold_count]
      assert_includes [true, false], result[:retention_audit_trigger_enabled]
      assert_includes [true, false], result[:legal_hold_audit_trigger_enabled]
    end

    test "assessment does not create or delete governance records" do
      assert_no_difference "Infrastructure::NotificationRetentionPolicy.count" do
        assert_no_difference "Infrastructure::NotificationLegalHold.count" do
          assert_no_difference "Infrastructure::NotificationRetentionEvent.count" do
            assert_no_difference "Infrastructure::NotificationLegalHoldEvent.count" do
              NotificationGovernanceSecurityAssessment.new.call
            end
          end
        end
      end
    end
  end
end
