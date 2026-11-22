# frozen_string_literal: true

require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationRetentionControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(username: "retention-test-#{SecureRandom.hex(8)}")
    end

    teardown do
      sign_out @user
    end

    test "unauthenticated user is redirected to login" do
      get infrastructure_notification_retention_path
      assert_redirected_to new_user_session_path
    end

    test "employee is denied access" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        get infrastructure_notification_retention_path
        assert_redirected_to root_path
      end
    end

    test "administrator sees retention dashboard" do
      as_admin do
        get infrastructure_notification_retention_path
        assert_response :success
        assert_select "#notification-retention-dashboard", 1
        assert_select "#notification-retention-kpis", 1
        assert_select "#notification-retention-protected", 1
      end
    end

    test "dashboard is read only" do
      as_admin do
        assert_no_difference -> { InfrastructureNotification.count } do
          assert_no_difference -> { InfrastructureNotificationAttempt.count } do
            get infrastructure_notification_retention_path
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
