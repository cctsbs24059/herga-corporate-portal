# frozen_string_literal: true
require "test_helper"
require "securerandom"
require "csv"

module Infrastructure
  class NotificationGovernanceComplianceControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(username: "compliance-#{SecureRandom.hex(8)}")
    end

    teardown { sign_out @user }

    test "guest cannot view compliance dashboard" do
      get infrastructure_notification_governance_compliance_path
      assert_redirected_to new_user_session_path
    end

    test "employee cannot export compliance evidence" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_roles, [:employee]) do
        get infrastructure_notification_governance_compliance_export_path(section: "summary")
        assert_redirected_to root_path
      end
    end

    test "administrator can view compliance dashboard" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_roles, [:portal_admin]) do
        get infrastructure_notification_governance_compliance_path
        assert_response :success
        assert_select "#notification-governance-compliance"
      end
    end

    test "administrator can export summary CSV" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_roles, [:portal_admin]) do
        get infrastructure_notification_governance_compliance_export_path(section: "summary")
        assert_response :success
        assert_includes response.media_type, "text/csv"
        assert_includes response.headers["Content-Disposition"], "attachment"
        assert_includes CSV.parse(response.body).first, "metric"
      end
    end

    test "invalid export section is rejected" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_roles, [:portal_admin]) do
        get infrastructure_notification_governance_compliance_export_path(section: "unknown")
        assert_response :bad_request
      end
    end
  end
end
