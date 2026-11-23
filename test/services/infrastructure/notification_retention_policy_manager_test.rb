# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class NotificationRetentionPolicyManagerTest < ActiveSupport::TestCase
    test "creation records draft event" do
      manager = NotificationRetentionPolicyManager.new(actor: "test-admin")
      policy = manager.create!(name: "Notification policy", reference: "POL-TEST-001", retention_days: 365)
      assert_equal "Draft", policy.status
      assert_equal 1, policy.events.count
      assert_equal "Created", policy.events.first.action
      assert_not policy.disposal_authorized?
    end

    test "approval and suspension create audit events" do
      manager = NotificationRetentionPolicyManager.new(actor: "test-admin")
      policy = manager.create!(name: "Notification policy", reference: "POL-TEST-002", retention_days: 365)
      manager.approve!(policy: policy, approval_reference: "POL-TEST-002")
      assert_equal "Approved", policy.reload.status
      assert_equal 2, policy.version
      manager.suspend!(policy: policy)
      assert_equal "Suspended", policy.reload.status
      assert_equal 3, policy.events.count
      assert_not policy.disposal_authorized?
    end

    test "cannot approve without matching reference" do
      manager = NotificationRetentionPolicyManager.new(actor: "test-admin")
      policy = manager.create!(name: "Notification policy", reference: "POL-TEST-003", retention_days: 365)
      assert_raises(NotificationRetentionPolicyManager::InvalidTransition) do
        manager.approve!(policy: policy, approval_reference: "OTHER")
      end
      assert_equal "Draft", policy.reload.status
      assert_equal 1, policy.events.count
    end

    test "cannot repeat approval" do
      manager = NotificationRetentionPolicyManager.new(actor: "test-admin")
      policy = manager.create!(name: "Notification policy", reference: "POL-TEST-004", retention_days: 365)
      manager.approve!(policy: policy, approval_reference: policy.reference)
      assert_raises(NotificationRetentionPolicyManager::InvalidTransition) do
        manager.approve!(policy: policy, approval_reference: policy.reference)
      end
    end

    test "persisted audit events are read only" do
      manager = NotificationRetentionPolicyManager.new(actor: "test-admin")
      policy = manager.create!(name: "Notification policy", reference: "POL-TEST-005", retention_days: 365)
      assert policy.events.first.readonly?
      assert_raises(ActiveRecord::ReadOnlyRecord) { policy.events.first.update!(actor: "someone-else") }
    end
  end
end
