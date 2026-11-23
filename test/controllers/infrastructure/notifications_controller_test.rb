# frozen_string_literal: true

require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(
        username: "notification-test-#{SecureRandom.hex(6)}"
      )

      @now = Time.zone.parse("2026-11-22 12:00:00 UTC")
    end

    teardown do
      sign_out @user
    end

    private

    def with_role(role)
      ActiveDirectoryAuthenticator.stub(:current_roles, (role == :admin ? [:portal_admin] : (role == :employee ? [:employee] : nil))) do
        yield
      end
    end

    def as_role(role)
      sign_in @user

      with_role(role) do
        yield
      end
    ensure
      sign_out @user
    end

    def create_notification(
      status: "Pending",
      occurred_at: @now,
      last_attempt_at: nil,
      accepted_at: nil,
      event_type: "IncidentOpened"
    )
      InfrastructureNotification.create!(
        event_key: "TEST-#{SecureRandom.uuid}",
        source_type: "InfrastructureAsset",
        source_id: 1,
        event_type: event_type,
        recipient: "notification-test@example.com",
        occurred_at: occurred_at,
        status: status,
        last_attempt_at: last_attempt_at,
        accepted_at: accepted_at
      )
    end

    def assert_history_ids(*notifications)
      expected_ids = notifications.map(&:id).map(&:to_s)

      actual_ids = css_select(
        "#notification-history-table tbody tr td:first-child"
      ).map { |cell| cell.text.strip }

      assert_equal expected_ids.sort, actual_ids.sort
    end

    public

    # ========================================================
    # 1. AUTHENTICATION AND AUTHORISATION
    # ========================================================

    test "unauthenticated user is redirected to login" do
      get infrastructure_notifications_path

      assert_redirected_to new_user_session_path
    end

    test "administrator can access notification centre" do
      as_role(:admin) do
        get infrastructure_notifications_path

        assert_response :success
        assert_select "h1", text: /Infrastructure Notification Centre/
      end
    end

    test "administrator can view notification details" do
      notification = create_notification

      as_role(:admin) do
        get infrastructure_notification_path(notification)

        assert_response :success
        assert_select "h1", text: /Notification ##{notification.id}/
      end
    end

    test "ordinary employee cannot access notification centre" do
      as_role(:employee) do
        get infrastructure_notifications_path

        assert_redirected_to root_path
      end
    end

    test "ordinary employee cannot access notification details" do
      notification = create_notification

      as_role(:employee) do
        get infrastructure_notification_path(notification)

        assert_redirected_to root_path
      end
    end

    test "unverified directory membership denies access" do
      as_role(nil) do
        get infrastructure_notifications_path

        assert_redirected_to new_user_session_path
      end
    end

    # ========================================================
    # 2. OPERATIONAL DASHBOARD COUNTERS
    # ========================================================

    test "dashboard displays unknown notification count" do
      travel_to @now do
        create_notification(status: "Unknown")

        as_role(:admin) do
          get infrastructure_notifications_path

          assert_response :success
          assert_select ".card", text: /Unknown Outcomes.*1/m
        end
      end
    end

    test "dashboard detects stale sending notifications" do
      travel_to @now do
        create_notification(
          status: "Sending",
          last_attempt_at: 31.minutes.ago
        )

        create_notification(
          status: "Sending",
          last_attempt_at: 10.minutes.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path

          assert_response :success
          assert_select ".card", text: /Stale Sending.*1/m
        end
      end
    end

    test "dashboard detects old pending notifications" do
      travel_to @now do
        create_notification(
          status: "Pending",
          occurred_at: 31.minutes.ago
        )

        create_notification(
          status: "Pending",
          occurred_at: 10.minutes.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path

          assert_response :success
          assert_select ".card", text: /Old Pending.*1/m
        end
      end
    end

    test "dashboard counts accepted submissions in last 24 hours" do
      travel_to @now do
        create_notification(
          status: "Accepted",
          accepted_at: 1.hour.ago
        )

        create_notification(
          status: "Accepted",
          accepted_at: 25.hours.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path

          assert_response :success
          assert_select ".card",
                        text: /Accepted - Last 24 Hours.*1/m
        end
      end
    end

    # ========================================================
    # 3. EXISTING SEARCH AND FILTERING
    # ========================================================

    test "status filter returns matching notifications" do
      accepted = create_notification(status: "Accepted")
      create_notification(status: "Pending")

      as_role(:admin) do
        get infrastructure_notifications_path,
            params: { status: "Accepted" }

        assert_response :success
        assert_history_ids accepted
      end
    end

    test "search finds notification by event key" do
      notification = create_notification

      as_role(:admin) do
        get infrastructure_notifications_path,
            params: { q: notification.event_key }

        assert_response :success
        assert_history_ids notification
      end
    end

    # ========================================================
    # 4. PRECISE OPERATIONAL ATTENTION FILTERING
    # ========================================================

    test "unknown attention filter returns only unknown records" do
      unknown = create_notification(status: "Unknown")
      create_notification(status: "Pending")
      create_notification(status: "Accepted")

      as_role(:admin) do
        get infrastructure_notifications_path,
            params: { attention: "unknown" }

        assert_response :success
        assert_history_ids unknown

        assert_select ".alert", text: /Operational Filter Active:/
      end
    end

    test "stale sending filter excludes recent sending records" do
      travel_to @now do
        stale = create_notification(
          status: "Sending",
          last_attempt_at: 31.minutes.ago
        )

        create_notification(
          status: "Sending",
          last_attempt_at: 10.minutes.ago
        )

        create_notification(status: "Pending")

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "stale_sending" }

          assert_response :success
          assert_history_ids stale
        end
      end
    end

    test "old pending filter excludes recent pending records" do
      travel_to @now do
        old = create_notification(
          status: "Pending",
          occurred_at: 31.minutes.ago
        )

        create_notification(
          status: "Pending",
          occurred_at: 10.minutes.ago
        )

        create_notification(status: "Sending")

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "old_pending" }

          assert_response :success
          assert_history_ids old
        end
      end
    end

    test "recent accepted filter excludes older submissions" do
      travel_to @now do
        recent = create_notification(
          status: "Accepted",
          accepted_at: 1.hour.ago
        )

        create_notification(
          status: "Accepted",
          accepted_at: 25.hours.ago
        )

        create_notification(status: "Pending")

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "recent_accepted" }

          assert_response :success
          assert_history_ids recent
        end
      end
    end

    test "stale sending includes exactly thirty minute boundary" do
      travel_to @now do
        boundary = create_notification(
          status: "Sending",
          last_attempt_at: 30.minutes.ago
        )

        create_notification(
          status: "Sending",
          last_attempt_at: 29.minutes.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "stale_sending" }

          assert_response :success
          assert_history_ids boundary
        end
      end
    end

    test "old pending includes exactly thirty minute boundary" do
      travel_to @now do
        boundary = create_notification(
          status: "Pending",
          occurred_at: 30.minutes.ago
        )

        create_notification(
          status: "Pending",
          occurred_at: 29.minutes.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "old_pending" }

          assert_response :success
          assert_history_ids boundary
        end
      end
    end

    test "recent accepted includes twenty four hour boundary" do
      travel_to @now do
        boundary = create_notification(
          status: "Accepted",
          accepted_at: 24.hours.ago
        )

        create_notification(
          status: "Accepted",
          accepted_at: 25.hours.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "recent_accepted" }

          assert_response :success
          assert_history_ids boundary
        end
      end
    end

    test "attention filter is preserved in search form" do
      travel_to @now do
        create_notification(
          status: "Sending",
          last_attempt_at: 31.minutes.ago
        )

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "stale_sending" }

          assert_response :success

          assert_select(
            'input[name="attention"][value="stale_sending"]',
            count: 1
          )
        end
      end
    end

    test "attention filter is preserved in pagination links" do
      travel_to @now do
        26.times do
          create_notification(status: "Unknown")
        end

        as_role(:admin) do
          get infrastructure_notifications_path,
              params: { attention: "unknown" }

          assert_response :success

          assert_select 'a[href*="attention=unknown"][href*="page=2"]',
                        text: "Next"
        end
      end
    end

    test "invalid attention filter falls back to normal history" do
      notification = create_notification

      as_role(:admin) do
        get infrastructure_notifications_path,
            params: { attention: "invalid_filter" }

        assert_response :success
        assert_history_ids notification

        assert_select ".alert",
                      text: /Operational Filter Active:/,
                      count: 0
      end
    end

    test "attention filter combines with event type filter" do
      matching = create_notification(
        status: "Unknown",
        event_type: "IncidentOpened"
      )

      create_notification(
        status: "Unknown",
        event_type: "IncidentRecovered"
      )

      as_role(:admin) do
        get infrastructure_notifications_path,
            params: {
              attention: "unknown",
              event_type: "IncidentOpened"
            }

        assert_response :success
        assert_history_ids matching
      end
    end

    # ========================================================
    # 5. READ-ONLY INTEGRITY
    # ========================================================

    test "dashboard does not change notification status" do
      notification = create_notification(status: "Unknown")
      original_updated_at = notification.updated_at

      as_role(:admin) do
        get infrastructure_notifications_path

        assert_response :success
      end

      notification.reload

      assert_equal "Unknown", notification.status
      assert_equal original_updated_at, notification.updated_at
    end

    test "dashboard does not create delivery attempts" do
      create_notification

      before_count = InfrastructureNotificationAttempt.count

      as_role(:admin) do
        get infrastructure_notifications_path

        assert_response :success
      end

      assert_equal before_count,
                   InfrastructureNotificationAttempt.count
    end

    test "operational filtering does not modify notifications" do
      notification = create_notification(status: "Unknown")

      original_updated_at = notification.updated_at
      original_attempt_count = notification.attempt_count

      as_role(:admin) do
        get infrastructure_notifications_path,
            params: { attention: "unknown" }

        assert_response :success
      end

      notification.reload

      assert_equal "Unknown", notification.status
      assert_equal original_updated_at, notification.updated_at
      assert_equal original_attempt_count, notification.attempt_count
    end

    test "operational filtering does not create audit attempts" do
      create_notification(status: "Unknown")

      as_role(:admin) do
        assert_no_difference "InfrastructureNotificationAttempt.count" do
          get infrastructure_notifications_path,
              params: { attention: "unknown" }
        end

        assert_response :success
      end
    end
  end
end
