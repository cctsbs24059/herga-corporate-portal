
# frozen_string_literal: true

require "test_helper"
require "securerandom"

class PortalRbacEnforcementTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      username: "rbac-enforcement-#{SecureRandom.hex(8)}"
    )
  end

  teardown do
    sign_out @user
  end

  # ==========================================================
  # INFRASTRUCTURE READ ACCESS
  # ==========================================================

  test "infrastructure administrator can view assets" do
    as_roles(:infrastructure_admin) do
      get infrastructure_assets_path
      assert_response :success
    end
  end

  test "auditor can view infrastructure assets" do
    as_roles(:auditor) do
      get infrastructure_assets_path
      assert_response :success
    end
  end

  test "employee cannot view infrastructure assets" do
    as_roles(:employee) do
      get infrastructure_assets_path
      assert_redirected_to root_path
    end
  end

  # ==========================================================
  # INFRASTRUCTURE MANAGEMENT
  # ==========================================================

  test "infrastructure administrator can access new asset form" do
    as_roles(:infrastructure_admin) do
      get new_infrastructure_asset_path
      assert_response :success
    end
  end

  test "auditor cannot access new asset form" do
    as_roles(:auditor) do
      get new_infrastructure_asset_path
      assert_redirected_to root_path
    end
  end

  test "security administrator cannot access new asset form" do
    as_roles(:security_admin) do
      get new_infrastructure_asset_path
      assert_redirected_to root_path
    end
  end

  # ==========================================================
  # GOVERNANCE READ ACCESS
  # ==========================================================

  test "security administrator can view retention policies" do
    as_roles(:security_admin) do
      get infrastructure_notification_retention_policies_path
      assert_response :success
    end
  end

  test "auditor can view retention policies" do
    as_roles(:auditor) do
      get infrastructure_notification_retention_policies_path
      assert_response :success
    end
  end

  test "infrastructure administrator cannot view retention policies" do
    as_roles(:infrastructure_admin) do
      get infrastructure_notification_retention_policies_path
      assert_redirected_to root_path
    end
  end

  # ==========================================================
  # GOVERNANCE MANAGEMENT
  # ==========================================================

  test "security administrator can access new retention policy form" do
    as_roles(:security_admin) do
      get new_infrastructure_notification_retention_policy_path
      assert_response :success
    end
  end

  test "auditor cannot access new retention policy form" do
    as_roles(:auditor) do
      get new_infrastructure_notification_retention_policy_path
      assert_redirected_to root_path
    end
  end

  test "infrastructure administrator cannot create retention policy" do
    as_roles(:infrastructure_admin) do
      assert_no_difference(
        "Infrastructure::NotificationRetentionPolicy.count"
      ) do
        post infrastructure_notification_retention_policies_path,
             params: {
               policy: {
                 name: "Unauthorized Policy",
                 reference: "DEN-#{SecureRandom.hex(4)}",
                 retention_days: 365
               }
             }
      end

      assert_redirected_to root_path
    end
  end

  # ==========================================================
  # GOVERNANCE EVIDENCE
  # ==========================================================

  test "auditor can export compliance evidence" do
    as_roles(:auditor) do
      get infrastructure_notification_governance_compliance_export_path(
        section: "summary"
      )

      assert_response :success
      assert_equal "text/csv", response.media_type
    end
  end

  test "employee cannot export compliance evidence" do
    as_roles(:employee) do
      get infrastructure_notification_governance_compliance_export_path(
        section: "summary"
      )

      assert_redirected_to root_path
    end
  end

  test "infrastructure administrator cannot export compliance evidence" do
    as_roles(:infrastructure_admin) do
      get infrastructure_notification_governance_compliance_export_path(
        section: "summary"
      )

      assert_redirected_to root_path
    end
  end

  # ==========================================================
  # MULTI-ROLE AUTHORIZATION
  # ==========================================================

  test "multiple roles combine infrastructure and governance permissions" do
    as_roles(:infrastructure_admin, :security_admin) do
      get new_infrastructure_asset_path
      assert_response :success

      get new_infrastructure_notification_retention_policy_path
      assert_response :success
    end
  end

  # ==========================================================
  # FAIL-CLOSED AUTHORIZATION
  # ==========================================================

  test "nil AD roles terminate the session" do
    as_roles(nil) do
      get infrastructure_assets_path
      assert_redirected_to new_user_session_path
    end
  end

  test "empty AD roles terminate the session" do
    as_roles([]) do
      get infrastructure_assets_path
      assert_redirected_to new_user_session_path
    end
  end

  test "unknown AD role terminates the session" do
    as_roles(:unknown_role) do
      get infrastructure_assets_path
      assert_redirected_to new_user_session_path
    end
  end

  # ==========================================================
  # HELPERS
  # ==========================================================

  private

  def as_roles(*roles)
    sign_in @user

    resolved_roles =
      if roles == [nil]
        nil
      elsif roles == [[]]
        []
      else
        roles
      end

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      resolved_roles
    ) do
      yield
    end
  end
end
