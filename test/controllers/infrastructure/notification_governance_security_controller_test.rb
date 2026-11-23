# frozen_string_literal: true
require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationGovernanceSecurityControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(username: "governance-security-#{SecureRandom.hex(8)}")
    end

    teardown { sign_out @user }

    test "guest cannot access security dashboard" do
      get infrastructure_notification_governance_security_path
      assert_redirected_to new_user_session_path
    end

    test "employee cannot access security dashboard" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        get infrastructure_notification_governance_security_path
        assert_redirected_to root_path
      end
    end

    test "administrator can view read only security dashboard" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :admin) do
        get infrastructure_notification_governance_security_path
        assert_response :success
        assert_select "#notification-governance-security"
        assert_select "form[action*='release']", count: 0
      end
    end
  end
end
