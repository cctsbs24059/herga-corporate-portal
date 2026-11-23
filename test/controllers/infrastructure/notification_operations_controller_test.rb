
# frozen_string_literal: true

require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationOperationsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(
        username: "operations-test-#{SecureRandom.hex(8)}"
      )
    end

    teardown do
      sign_out @user
    end

    test "unauthenticated user redirects to login" do
      get infrastructure_notification_operations_path

      assert_redirected_to new_user_session_path
    end

    test "employee cannot access operations dashboard" do
      sign_in @user

      ActiveDirectoryAuthenticator.stub(:current_roles, [:employee]) do
        get infrastructure_notification_operations_path

        assert_redirected_to root_path
      end
    end

    test "administrator can view dashboard" do
      as_admin do
        get infrastructure_notification_operations_path

        assert_response :success
        assert_select "h1", text: /Notification Operations/
        assert_select "#notification-operations-kpis", 1
        assert_select "#notification-operations-jobs", 1
        assert_select "#notification-operations-queue", 1
      end
    end

    test "administrator sees links to all operational modules" do
      as_admin do
        get infrastructure_notification_operations_path

        assert_response :success

        links = css_select(
          "#notification-operations-modules a"
        ).map { |element| element["href"] }

        assert_includes links,
                        infrastructure_notifications_path

        assert_includes links,
                        infrastructure_notification_analytics_path(
                          period: "7d"
                        )

        assert_includes links,
                        infrastructure_notification_job_failures_path

        assert_includes links,
                        infrastructure_notification_reports_path(
                          period: "7d"
                        )
      end
    end

    test "all reporting periods are linked" do
      as_admin do
        get infrastructure_notification_operations_path

        assert_response :success

        links = css_select("a").map do |element|
          element["href"]
        end

        %w[24h 7d 30d 90d].each do |period|
          expected_path =
            infrastructure_notification_operations_path(
              period: period
            )

          assert_includes links, expected_path
        end
      end
    end

    test "invalid period falls back to seven days" do
      as_admin do
        get infrastructure_notification_operations_path(
          period: "invalid"
        )

        assert_response :success

        links = css_select("a").map do |element|
          element["href"]
        end

        expected_path =
          infrastructure_notification_operations_path(
            period: "7d"
          )

        assert_includes links, expected_path
      end
    end

    test "dashboard does not create notification or attempt records" do
      as_admin do
        assert_no_difference -> { InfrastructureNotification.count } do
          assert_no_difference -> { InfrastructureNotificationAttempt.count } do

            get infrastructure_notification_operations_path(
              period: "24h"
            )

            assert_response :success
          end
        end
      end
    end

    private

    def as_admin
      sign_in @user

      ActiveDirectoryAuthenticator.stub(:current_roles, [:portal_admin]
      ) do
        yield
      end
    end
  end
end
