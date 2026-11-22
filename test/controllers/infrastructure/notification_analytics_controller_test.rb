# frozen_string_literal: true

require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationAnalyticsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(username: "analytics-test-#{SecureRandom.hex(8)}")
    end

    teardown do
      sign_out @user
    end

    test "unauthenticated access redirects to login" do
      get infrastructure_notification_analytics_path
      assert_redirected_to new_user_session_path
    end

    test "employee access redirects to dashboard" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        get infrastructure_notification_analytics_path
        assert_redirected_to root_path
      end
    end

    test "administrator can access analytics dashboard" do
      as_admin do
        get infrastructure_notification_analytics_path
        assert_response :success
        assert_select "h1", text: /Notification Operational Analytics/
        assert_select "#notification-analytics-daily-table", 1
        assert_select "a[href='#{infrastructure_notifications_path}']", minimum: 1
      end
    end

    test "all reporting period links render" do
      as_admin do
        get infrastructure_notification_analytics_path
        assert_response :success
        %w[24h 7d 30d 90d].each do |period|
          assert_select "a[href='#{infrastructure_notification_analytics_path(period: period)}']", minimum: 1
        end
      end
    end

    test "selected reporting period appears in refresh link" do
      as_admin do
        get infrastructure_notification_analytics_path(period: "30d")
        assert_response :success
        assert_select "a[href='#{infrastructure_notification_analytics_path(period: '30d')}']", minimum: 1
      end
    end

    test "invalid reporting period falls back to seven days" do
      as_admin do
        get infrastructure_notification_analytics_path(period: "bogus")
        assert_response :success
        assert_select "a[href='#{infrastructure_notification_analytics_path(period: '7d')}']", minimum: 1
      end
    end

    test "empty period renders safely" do
      as_admin do
        travel_to Time.utc(2035, 6, 15, 12) do
          get infrastructure_notification_analytics_path(period: "24h")
          assert_response :success
          assert_select "#notification-analytics-daily-table tbody", text: /No notifications in this reporting period/
        end
      end
    end

    test "administrator request does not modify notification or attempt records" do
      as_admin do
        assert_no_difference -> { InfrastructureNotification.count } do
          assert_no_difference -> { InfrastructureNotificationAttempt.count } do
            get infrastructure_notification_analytics_path(period: "7d")
            assert_response :success
          end
        end
      end
    end

    private

    def as_admin
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :admin) { yield }
    end
  end
end
