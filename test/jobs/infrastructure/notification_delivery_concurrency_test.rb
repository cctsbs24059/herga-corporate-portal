
# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "timeout"

# ============================================================
# HERGA CORPORATE PORTAL
# Infrastructure Notification Delivery Concurrency Tests
#
# Phase 2D.8.3.3
#
# Purpose:
# Verify that simultaneous job execution cannot produce
# duplicate Microsoft Graph submissions.
# ============================================================

class InfrastructureNotificationDeliveryConcurrencyTest <
  ActiveSupport::TestCase

  self.use_transactional_tests = false

  setup do
    @now = Time.current

    @original_enabled =
      ENV["HERGA_NOTIFICATIONS_ENABLED"]

    @original_start =
      ENV["HERGA_NOTIFICATIONS_START_AT"]

    ENV["HERGA_NOTIFICATIONS_ENABLED"] = "true"

    ENV["HERGA_NOTIFICATIONS_START_AT"] =
      (@now - 2.hours).iso8601
  end

  teardown do
    if @notification
      InfrastructureNotificationAttempt
        .where(infrastructure_notification_id: @notification.id)
        .delete_all

      InfrastructureNotification
        .where(id: @notification.id)
        .delete_all
    end

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
  # Two workers attempt delivery simultaneously.
  #
  # A synchronized start allows both workers to race
  # for the same Pending notification.
  #
  # The winning worker is held inside the Graph mock,
  # allowing the losing worker to attempt its claim.
  # ==========================================================

  test "two concurrent workers submit only one Graph request" do
    @notification = create_notification

    mutex = Mutex.new
    condition = ConditionVariable.new

    ready = 0
    released = false
    graph_entered = false
    graph_calls = 0

    sender = Object.new

    sender.define_singleton_method(:deliver!) do |**_arguments|
      mutex.synchronize do
        graph_calls += 1
        graph_entered = true
        condition.broadcast

        until released
          condition.wait(mutex)
        end
      end

      true
    end

    message = fake_mailer_message
    mailer_delivery = Struct.new(:message).new(message)

    worker_errors = Queue.new

    InfrastructureNotificationMailer.stub(
      :event,
      ->(_notification_id) { mailer_delivery }
    ) do
      Infrastructure::MicrosoftGraphMailSender.stub(
        :new,
        -> { sender }
      ) do
        threads = 2.times.map do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              begin
                mutex.synchronize do
                  ready += 1
                  condition.broadcast

                  condition.wait(mutex) until ready == 2
                end

                Infrastructure::NotificationDeliveryJob
                  .new
                  .perform(@notification.id)
              rescue StandardError => e
                worker_errors << e
              end
            end
          end
        end

        begin
          Timeout.timeout(15) do
            mutex.synchronize do
              condition.wait(mutex) until graph_entered
            end
          end

          # The first worker has reached Microsoft Graph.
          # Allow the second worker time to complete its
          # competing database claim.
          Timeout.timeout(15) do
            loop do
              break if threads.count(&:alive?) == 1

              sleep 0.01
            end
          end

        ensure
          mutex.synchronize do
            released = true
            condition.broadcast
          end

          threads.each(&:join)
        end
      end
    end

    assert worker_errors.empty?,
           "Worker errors: #{worker_errors.size}"

    @notification.reload

    assert_equal 1, graph_calls
    assert_equal "Accepted", @notification.status
    assert_equal 1, @notification.attempt_count

    assert_equal(
      1,
      @notification.infrastructure_notification_attempts.count
    )

    assert_equal(
      "Accepted",
      @notification.infrastructure_notification_attempts.first.status
    )
  end

  # ==========================================================
  # TEST HELPERS
  # ==========================================================

  private

  def create_notification
    InfrastructureNotification.create!(
      event_key: "HERGA-CONCURRENCY-#{SecureRandom.uuid}",
      source_type: "InfrastructureIncident",
      source_id: 1,
      event_type: "IncidentOpened",
      recipient: Infrastructure::NotificationSettings::RECIPIENT,
      occurred_at: @now - 1.hour,
      status: "Pending",
      attempt_count: 0
    )
  end

  def fake_mailer_message
    body = Struct.new(:decoded).new(
      "HERGA concurrency test body"
    )

    Struct.new(:subject, :body) do
      def multipart?
        false
      end
    end.new(
      "HERGA Concurrency Test",
      body
    )
  end

  def restore_env(name, original)
    if original.nil?
      ENV.delete(name)
    else
      ENV[name] = original
    end
  end
end

