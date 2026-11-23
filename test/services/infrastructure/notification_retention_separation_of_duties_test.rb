# frozen_string_literal: true
require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationRetentionSeparationOfDutiesTest < ActiveSupport::TestCase
    def create_policy(actor: "creator-admin")
      NotificationRetentionPolicyManager.new(actor: actor).create!(
        name: "Independent approval test", reference: "SOD-#{SecureRandom.hex(8)}", retention_days: 365
      )
    end

    test "creator cannot approve own policy" do
      policy = create_policy
      assert_raises(NotificationRetentionPolicyManager::InvalidTransition) do
        NotificationRetentionPolicyManager.new(actor: "creator-admin").approve!(policy: policy, approval_reference: policy.reference)
      end
      assert_equal "Draft", policy.reload.status
      assert_equal 1, policy.events.count
    end

    test "creator comparison ignores username case" do
      policy = create_policy(actor: "Creator-Admin")
      assert_raises(NotificationRetentionPolicyManager::InvalidTransition) do
        NotificationRetentionPolicyManager.new(actor: "CREATOR-ADMIN").approve!(policy: policy, approval_reference: policy.reference)
      end
    end

    test "different administrator can approve" do
      policy = create_policy
      NotificationRetentionPolicyManager.new(actor: "reviewer-admin").approve!(policy: policy, approval_reference: policy.reference)
      assert_equal "Approved", policy.reload.status
      assert_equal "reviewer-admin", policy.approved_by
      assert_equal 2, policy.events.count
      assert_not policy.disposal_authorized?
    end

    test "missing creation evidence prevents approval" do
      policy = Infrastructure::NotificationRetentionPolicy.create!(
        name: "Legacy draft", reference: "LEGACY-#{SecureRandom.hex(8)}", retention_days: 365,
        status: "Draft", version: 1
      )
      assert_raises(NotificationRetentionPolicyManager::InvalidTransition) do
        NotificationRetentionPolicyManager.new(actor: "reviewer-admin").approve!(policy: policy, approval_reference: policy.reference)
      end
      assert_equal "Draft", policy.reload.status
    end
  end
end
