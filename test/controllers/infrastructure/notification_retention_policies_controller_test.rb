# frozen_string_literal: true
require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationRetentionPoliciesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(username: "policy-ui-#{SecureRandom.hex(8)}")
    end

    teardown { sign_out @user }

    test "guest is redirected to sign in" do
      get infrastructure_notification_retention_policies_path
      assert_redirected_to new_user_session_path
    end

    test "employee cannot create policy" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        assert_no_difference "Infrastructure::NotificationRetentionPolicy.count" do
          post infrastructure_notification_retention_policies_path,
               params: { policy: { name: "Denied", reference: "DEN-#{SecureRandom.hex(4)}", retention_days: 365 } }
        end
        assert_redirected_to root_path
      end
    end

    test "admin creates draft and audit event" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :admin) do
        assert_difference "Infrastructure::NotificationRetentionPolicy.count", 1 do
          assert_difference "Infrastructure::NotificationRetentionEvent.count", 1 do
            post infrastructure_notification_retention_policies_path,
                 params: { policy: { name: "Test Policy", reference: "UI-#{SecureRandom.hex(4)}", retention_days: 365 } }
          end
        end
        assert_response :redirect
        assert_equal "Draft", Infrastructure::NotificationRetentionPolicy.order(:id).last.status
      end
    end

    test "admin can view policy listing" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :admin) do
        get infrastructure_notification_retention_policies_path
        assert_response :success
        assert_select "#retention-policies"
      end
    end
  end
end
