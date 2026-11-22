
# frozen_string_literal: true

require "test_helper"

# ============================================================
# HERGA CORPORATE PORTAL
# Infrastructure Notification Reconciler Tests
#
# Phase 2D.8.3.3
# Notification Reliability & Operational Controls
# ============================================================

class InfrastructureNotificationReconcilerTest < ActiveSupport::TestCase

  # ==========================================================
  # 1. NOTIFICATION ACTIVATION CONTROLS
  # ==========================================================

  test "notifications are disabled without an activation timestamp" do
    with_notification_env(
      enabled: "true",
      start_at: nil
    ) do
      assert_not Infrastructure::NotificationSettings.enabled?

      result = Infrastructure::NotificationReconciler.new.call

      assert_equal(
        {
          enabled: false,
          created: 0,
          recovered: 0
        },
        result
      )
    end
  end

  test "notifications are disabled when feature flag is false" do
    with_notification_env(
      enabled: "false",
      start_at: 1.hour.ago.iso8601
    ) do
      assert_not Infrastructure::NotificationSettings.enabled?

      result = Infrastructure::NotificationReconciler.new.call

      assert_equal(
        {
          enabled: false,
          created: 0,
          recovered: 0
        },
        result
      )
    end
  end

  test "notifications are disabled when activation timestamp is invalid" do
    with_notification_env(
      enabled: "true",
      start_at: "invalid-timestamp"
    ) do
      assert_not Infrastructure::NotificationSettings.enabled?

      result = Infrastructure::NotificationReconciler.new.call

      assert_equal(
        {
          enabled: false,
          created: 0,
          recovered: 0
        },
        result
      )
    end
  end

  test "notification reconciliation does not run before activation time" do
    now = Time.current

    with_notification_env(
      enabled: "true",
      start_at: (now + 1.hour).iso8601
    ) do
      # A valid future timestamp must be parsed correctly.
      activation_time =
        Infrastructure::NotificationSettings.activation_time

      assert_not_nil activation_time
      assert_operator activation_time, :>, now

      # The reconciler must not create or recover
      # notifications before the activation timestamp.
      result = Infrastructure::NotificationReconciler.new.call(
        now: now
      )

      assert_equal(
        {
          enabled: false,
          created: 0,
          recovered: 0
        },
        result
      )
    end
  end

  # ==========================================================
  # 2. NOTIFICATION RECIPIENT CONFIGURATION
  # ==========================================================

  test "notification recipient is the configured HERGA mailbox" do
    assert_equal(
      "info@hergafarmsgroup.com",
      Infrastructure::NotificationSettings::RECIPIENT
    )
  end

  # ==========================================================
  # 3. ESCALATION CONFIGURATION
  # ==========================================================

  test "notification escalation interval is positive" do
    assert_operator(
      Infrastructure::NotificationSettings.escalation_minutes,
      :>=,
      1
    )
  end

  test "notification escalation interval does not exceed maximum" do
    assert_operator(
      Infrastructure::NotificationSettings.escalation_minutes,
      :<=,
      1440
    )
  end

  # ==========================================================
  # 4. ENVIRONMENT VARIABLE TEST HELPERS
  # ==========================================================

  private

  def with_notification_env(enabled:, start_at:)
    previous_enabled =
      ENV["HERGA_NOTIFICATIONS_ENABLED"]

    previous_start =
      ENV["HERGA_NOTIFICATIONS_START_AT"]

    ENV["HERGA_NOTIFICATIONS_ENABLED"] = enabled

    if start_at.nil?
      ENV.delete("HERGA_NOTIFICATIONS_START_AT")
    else
      ENV["HERGA_NOTIFICATIONS_START_AT"] = start_at
    end

    yield

  ensure
    if previous_enabled.nil?
      ENV.delete("HERGA_NOTIFICATIONS_ENABLED")
    else
      ENV["HERGA_NOTIFICATIONS_ENABLED"] = previous_enabled
    end

    if previous_start.nil?
      ENV.delete("HERGA_NOTIFICATIONS_START_AT")
    else
      ENV["HERGA_NOTIFICATIONS_START_AT"] = previous_start
    end
  end
end
