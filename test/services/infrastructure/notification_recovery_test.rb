
# frozen_string_literal: true

require "test_helper"

# ============================================================
# HERGA CORPORATE PORTAL
# Infrastructure Notification Recovery Tests
#
# Phase 2D.8.3.3
# Notification Reliability & Operational Controls
# ============================================================

class InfrastructureNotificationRecoveryTest < ActiveSupport::TestCase
  setup do
    @now = Time.current
    @recovery = Infrastructure::NotificationRecovery.new
  end

  # ==========================================================
  # TEST 1
  # Stale Sending notifications must transition to Unknown.
  # ==========================================================

  test "recovers stale sending notification" do
    notification = create_notification(
      status: "Sending",
      attempted_at: @now - 45.minutes
    )

    result = @recovery.call(now: @now)

    notification.reload

    assert_equal 1, result[:recovered]
    assert_equal "Unknown", notification.status
    assert_equal 1, notification.attempt_count
    assert_match(/Manual investigation required/, notification.last_error)
  end

  # ==========================================================
  # TEST 2
  # Recent Sending notifications must not be recovered.
  # ==========================================================

  test "does not recover recently started delivery" do
    notification = create_notification(
      status: "Sending",
      attempted_at: @now - 5.minutes
    )

    result = @recovery.call(now: @now)

    assert_equal 0, result[:recovered]
    assert_equal "Sending", notification.reload.status
    assert_equal 0, notification.infrastructure_notification_attempts.count
  end

  # ==========================================================
  # TEST 3
  # Pending notifications must remain untouched.
  # ==========================================================

  test "does not recover pending notification" do
    notification = create_notification(
      status: "Pending",
      attempted_at: @now - 45.minutes
    )

    result = @recovery.call(now: @now)

    assert_equal 0, result[:recovered]
    assert_equal "Pending", notification.reload.status
  end

  # ==========================================================
  # TEST 4
  # Accepted notifications must remain untouched.
  # ==========================================================

  test "does not recover accepted notification" do
    notification = create_notification(
      status: "Accepted",
      attempted_at: @now - 45.minutes
    )

    result = @recovery.call(now: @now)

    assert_equal 0, result[:recovered]
    assert_equal "Accepted", notification.reload.status
  end

  # ==========================================================
  # TEST 5
  # Recovery must create an audit trail.
  # ==========================================================

  test "creates recovery audit record" do
    notification = create_notification(
      status: "Sending",
      attempted_at: @now - 45.minutes
    )

    assert_difference(
      "InfrastructureNotificationAttempt.count",
      1
    ) do
      @recovery.call(now: @now)
    end

    attempt =
      notification.infrastructure_notification_attempts.last

    assert_not_nil attempt
    assert_equal "Unknown", attempt.status
    assert_equal "StaleDeliveryRecovery", attempt.error_class
    assert_match(/Manual investigation required/, attempt.error_message)
  end

  # ==========================================================
  # TEST 6
  # Repeated recovery must not create duplicate audit records.
  # ==========================================================

  test "recovery is idempotent" do
    notification = create_notification(
      status: "Sending",
      attempted_at: @now - 45.minutes
    )

    first_result = @recovery.call(now: @now)
    second_result = @recovery.call(now: @now)

    assert_equal 1, first_result[:recovered]
    assert_equal 0, second_result[:recovered]

    assert_equal "Unknown", notification.reload.status

    assert_equal(
      1,
      notification.infrastructure_notification_attempts.count
    )
  end

  # ==========================================================
  # TEST 7
  # Recovery must not initiate email delivery.
  # ==========================================================

  test "recovery does not invoke Microsoft Graph" do
    notification = create_notification(
      status: "Sending",
      attempted_at: @now - 45.minutes
    )

    # If recovery tries to create a Graph sender, the test
    # fails immediately.
    Infrastructure::MicrosoftGraphMailSender.stub(
      :new,
      -> { flunk "Recovery must not invoke Microsoft Graph" }
    ) do
      result = @recovery.call(now: @now)

      assert_equal 1, result[:recovered]
    end

    assert_equal "Unknown", notification.reload.status
  end

  # ==========================================================
  # TEST HELPERS
  # ==========================================================

  private

  def create_notification(status:, attempted_at:)
    InfrastructureNotification.create!(
      event_key: "HERGA-RECOVERY-TEST-#{SecureRandom.uuid}",
      source_type: "InfrastructureIncident",
      source_id: 1,
      event_type: "IncidentOpened",
      recipient: Infrastructure::NotificationSettings::RECIPIENT,
      occurred_at: @now - 1.hour,
      status: status,
      attempted_at: attempted_at,
      attempt_count: 0
    )
  end
end
