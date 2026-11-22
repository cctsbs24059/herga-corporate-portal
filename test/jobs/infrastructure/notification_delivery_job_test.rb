
# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "securerandom"

# ============================================================
# HERGA CORPORATE PORTAL
# Infrastructure Notification Delivery Job Tests
#
# Phase 2D.8.3.3
# Microsoft Graph Delivery Reliability
#
# Tests:
#  1. Successful Graph submission
#  2. Graph submission failure
#  3. Duplicate delivery prevention
#  4. Unknown outcome protection
#  5. Activation cutoff enforcement
#  6. Future notification protection
#  7. Feature flag enforcement
#  8. Sending state protection
#  9. Transactional audit rollback
# ============================================================

class InfrastructureNotificationDeliveryJobTest < ActiveSupport::TestCase

  setup do
    @now = Time.current
    @job = Infrastructure::NotificationDeliveryJob.new

    @original_enabled = ENV["HERGA_NOTIFICATIONS_ENABLED"]
    @original_start = ENV["HERGA_NOTIFICATIONS_START_AT"]

    ENV["HERGA_NOTIFICATIONS_ENABLED"] = "true"
    ENV["HERGA_NOTIFICATIONS_START_AT"] =
      (@now - 2.hours).iso8601
  end

  teardown do
    restore_env(
      "HERGA_NOTIFICATIONS_ENABLED",
      @original_enabled
    )

    restore_env(
      "HERGA_NOTIFICATIONS_START_AT",
      @original_start
    )
  end

  # ==========================================================
  # TEST 1
  # Successful Graph submission must record Accepted.
  #
  # Graph arguments are captured and verified after the job
  # finishes, rather than asserting inside the Graph mock.
  #
  # Diagnostics are displayed if the job records Unknown.
  # ==========================================================

  test "successful Graph submission records Accepted status" do
    notification = create_notification

    deliveries = []

    sender = fake_sender do |to:, subject:, body:|
      deliveries << {
        to: to,
        subject: subject,
        body: body
      }

      true
    end

    with_delivery_dependencies(sender) do
      assert_difference(
        "InfrastructureNotificationAttempt.count",
        1
      ) do
        @job.perform(notification.id)
      end
    end

    notification.reload

    if notification.status != "Accepted"
      print_delivery_diagnostics(notification)
    end

    assert_equal 1, deliveries.length

    delivery = deliveries.first

    assert_equal notification.recipient, delivery[:to]

    assert_equal(
      "HERGA Test Notification",
      delivery[:subject]
    )

    assert_equal(
      "HERGA notification test body",
      delivery[:body]
    )

    assert_equal(
      "Accepted",
      notification.status,
      "Expected Graph acceptance. Last error: " \
      "#{notification.last_error.inspect}"
    )

    assert_not_nil notification.accepted_at
    assert_nil notification.last_error
    assert_equal 1, notification.attempt_count

    attempt =
      notification.infrastructure_notification_attempts.last

    assert_not_nil attempt
    assert_equal "Accepted", attempt.status
    assert_not_nil attempt.attempted_at
  end

  # ==========================================================
  # TEST 2
  # Graph submission failures must produce Unknown.
  # ==========================================================

  test "Graph submission failure records Unknown status" do
    notification = create_notification

    sender = fake_sender do |**_arguments|
      raise Infrastructure::MicrosoftGraphMailSender::SubmissionError,
            "Simulated Graph submission failure"
    end

    with_delivery_dependencies(sender) do
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal "Unknown", notification.status
    assert_equal 1, notification.attempt_count
    assert_nil notification.accepted_at

    assert_match(
      /Simulated Graph submission failure/,
      notification.last_error
    )

    attempt =
      notification.infrastructure_notification_attempts.last

    assert_not_nil attempt
    assert_equal "Unknown", attempt.status

    assert_equal(
      "Infrastructure::MicrosoftGraphMailSender::SubmissionError",
      attempt.error_class
    )
  end

  # ==========================================================
  # TEST 3
  # Accepted notifications must not be delivered twice.
  # ==========================================================

  test "accepted notification is not delivered twice" do
    notification = create_notification

    delivery_count = 0

    sender = fake_sender do |**_arguments|
      delivery_count += 1
      true
    end

    with_delivery_dependencies(sender) do
      @job.perform(notification.id)
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal 1, delivery_count
    assert_equal "Accepted", notification.status
    assert_equal 1, notification.attempt_count

    assert_equal(
      1,
      notification.infrastructure_notification_attempts.count
    )
  end

  # ==========================================================
  # TEST 4
  # Unknown notifications must not be resent.
  # ==========================================================

  test "Unknown notification is not automatically retried" do
    notification = create_notification(status: "Unknown")

    Infrastructure::MicrosoftGraphMailSender.stub(
      :new,
      -> {
        raise "Unknown notification must not be resent"
      }
    ) do
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal "Unknown", notification.status
    assert_equal 0, notification.attempt_count

    assert_equal(
      0,
      notification.infrastructure_notification_attempts.count
    )
  end

  # ==========================================================
  # TEST 5
  # Pre-activation notifications must not be delivered.
  # ==========================================================

  test "notification before activation cutoff is not delivered" do
    notification = create_notification(
      occurred_at: @now - 3.hours
    )

    Infrastructure::MicrosoftGraphMailSender.stub(
      :new,
      -> {
        raise "Pre-activation notification must not be sent"
      }
    ) do
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal "Pending", notification.status
    assert_equal 0, notification.attempt_count

    assert_equal(
      0,
      notification.infrastructure_notification_attempts.count
    )
  end

  # ==========================================================
  # TEST 6
  # Future notifications must not be delivered.
  # ==========================================================

  test "future notification is not delivered" do
    notification = create_notification(
      occurred_at: @now + 1.hour
    )

    Infrastructure::MicrosoftGraphMailSender.stub(
      :new,
      -> {
        raise "Future notification must not be sent"
      }
    ) do
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal "Pending", notification.status
    assert_equal 0, notification.attempt_count

    assert_equal(
      0,
      notification.infrastructure_notification_attempts.count
    )
  end

  # ==========================================================
  # TEST 7
  # Disabled notifications must not invoke Graph.
  # ==========================================================

  test "disabled notifications do not invoke Graph" do
    ENV["HERGA_NOTIFICATIONS_ENABLED"] = "false"

    notification = create_notification

    Infrastructure::MicrosoftGraphMailSender.stub(
      :new,
      -> {
        raise "Disabled notification must not be sent"
      }
    ) do
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal "Pending", notification.status
    assert_equal 0, notification.attempt_count
  end

  # ==========================================================
  # TEST 8
  # Already Sending notifications cannot be reclaimed.
  # ==========================================================

  test "Sending notification cannot be claimed again" do
    notification = create_notification(status: "Sending")

    Infrastructure::MicrosoftGraphMailSender.stub(
      :new,
      -> {
        raise "Sending notification must not be resent"
      }
    ) do
      @job.perform(notification.id)
    end

    notification.reload

    assert_equal "Sending", notification.status
    assert_equal 0, notification.attempt_count

    assert_equal(
      0,
      notification.infrastructure_notification_attempts.count
    )
  end

  # ==========================================================
  # TEST 9
  # Accepted audit failure must roll back acceptance.
  #
  # A before_create callback simulates a failure only for
  # Accepted audit records.
  #
  # The Unknown audit record must still be created.
  # ==========================================================

  test "audit failure rolls back Accepted status" do
    notification = create_notification

    delivery_count = 0

    sender = fake_sender do |**_arguments|
      delivery_count += 1
      true
    end

    failure_callback = proc do |attempt|
      if attempt.status == "Accepted"
        raise StandardError,
              "Simulated Accepted audit failure"
      end
    end

    InfrastructureNotificationAttempt.set_callback(
      :create,
      :before,
      failure_callback
    )

    begin
      with_delivery_dependencies(sender) do
        @job.perform(notification.id)
      end
    ensure
      InfrastructureNotificationAttempt.skip_callback(
        :create,
        :before,
        failure_callback
      )
    end

    notification.reload

    assert_equal 1, delivery_count

    assert_equal "Unknown", notification.status
    assert_nil notification.accepted_at
    assert_equal 1, notification.attempt_count

    assert_equal(
      1,
      notification.infrastructure_notification_attempts.count
    )

    attempt =
      notification.infrastructure_notification_attempts.first

    assert_equal "Unknown", attempt.status
    assert_equal "StandardError", attempt.error_class

    assert_match(
      /Simulated Accepted audit failure/,
      attempt.error_message
    )
  end

  # ==========================================================
  # TEST HELPERS
  # ==========================================================

  private

  def create_notification(
    status: "Pending",
    occurred_at: @now - 1.hour
  )
    InfrastructureNotification.create!(
      event_key: "HERGA-DELIVERY-TEST-#{SecureRandom.uuid}",
      source_type: "InfrastructureIncident",
      source_id: 1,
      event_type: "IncidentOpened",
      recipient: Infrastructure::NotificationSettings::RECIPIENT,
      occurred_at: occurred_at,
      status: status,
      attempt_count: 0
    )
  end

  def fake_sender(&block)
    sender = Object.new

    sender.define_singleton_method(
      :deliver!,
      &block
    )

    sender
  end

  # ==========================================================
  # Mock the email message generated by the mailer.
  # ==========================================================

  def fake_mailer_message
    body = Struct.new(:decoded).new(
      "HERGA notification test body"
    )

    Struct.new(:subject, :body) do
      def multipart?
        false
      end
    end.new(
      "HERGA Test Notification",
      body
    )
  end

  # ==========================================================
  # Mock both the mailer and Microsoft Graph sender.
  # ==========================================================

  def with_delivery_dependencies(sender)
    message = fake_mailer_message

    mailer_delivery =
      Struct.new(:message).new(message)

    InfrastructureNotificationMailer.stub(
      :event,
      ->(_notification_id) { mailer_delivery }
    ) do
      Infrastructure::MicrosoftGraphMailSender.stub(
        :new,
        -> { sender }
      ) do
        yield
      end
    end
  end

  # ==========================================================
  # Diagnostics for unexpected notification states.
  # ==========================================================

  def print_delivery_diagnostics(notification)
    puts
    puts "=" * 65
    puts "HERGA NOTIFICATION DELIVERY DIAGNOSTICS"
    puts "=" * 65

    puts "Notification ID: #{notification.id}"
    puts "Event key: #{notification.event_key}"
    puts "Status: #{notification.status}"
    puts "Attempt count: #{notification.attempt_count}"
    puts "Accepted at: #{notification.accepted_at.inspect}"
    puts "Last error: #{notification.last_error.inspect}"

    notification.infrastructure_notification_attempts.each do |attempt|
      puts "-" * 65
      puts "Audit ID: #{attempt.id}"
      puts "Audit status: #{attempt.status}"
      puts "Audit error class: #{attempt.error_class.inspect}"
      puts "Audit error message: #{attempt.error_message.inspect}"
    end

    puts "=" * 65
    puts
  end

  # ==========================================================
  # Restore environment variables after each test.
  # ==========================================================

  def restore_env(name, original)
    if original.nil?
      ENV.delete(name)
    else
      ENV[name] = original
    end
  end

end
