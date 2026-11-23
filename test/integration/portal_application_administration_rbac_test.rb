
# frozen_string_literal: true

require "test_helper"
require "securerandom"

# ================================================================
# HERGA CORPORATE PORTAL
# Application Administration RBAC Integration Tests
#
# Security requirements:
# - Only portal_admin may manage applications
# - Other AD roles must be denied
# - Local database admin flags must not grant access
# - Multiple AD roles must be supported
# - Failed AD role verification must deny access
# - Unauthorized requests must not change application data
# ================================================================

class PortalApplicationAdministrationRbacTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      username: "app-admin-rbac-#{SecureRandom.hex(8)}"
    )
  end

  teardown do
    sign_out @user
  end

  # ==============================================================
  # AUTHORIZED ACCESS
  # ==============================================================

  test "portal administrator can access application management" do
    as_roles(:portal_admin) do
      get admin_portal_applications_path,
          headers: html_headers

      assert_response :success
    end
  end

  test "portal administrator can access new application form" do
    as_roles(:portal_admin) do
      get new_admin_portal_application_path,
          headers: html_headers

      assert_response :success
    end
  end

  test "portal administrator with multiple roles can access management" do
    as_roles(:employee, :portal_admin) do
      get admin_portal_applications_path,
          headers: html_headers

      assert_response :success
    end
  end

  # ==============================================================
  # UNAUTHORIZED ACCESS
  # ==============================================================

  test "employee cannot access application management" do
    assert_management_denied_for(:employee)
  end

  test "infrastructure administrator cannot access application management" do
    assert_management_denied_for(:infrastructure_admin)
  end

  test "security administrator cannot access application management" do
    assert_management_denied_for(:security_admin)
  end

  test "auditor cannot access application management" do
    assert_management_denied_for(:auditor)
  end

  test "employee and auditor combined cannot access management" do
    as_roles(:employee, :auditor) do
      get admin_portal_applications_path,
          headers: html_headers

      assert_redirected_to root_path
    end
  end

  # ==============================================================
  # LOCAL DATABASE ADMINISTRATOR BYPASS PREVENTION
  # ==============================================================

  test "local administrator flag does not grant application management" do
    @user.update!(admin: true)

    as_roles(:employee) do
      get admin_portal_applications_path,
          headers: html_headers

      assert_redirected_to root_path
    end
  end

  # ==============================================================
  # FAILED ACTIVE DIRECTORY VERIFICATION
  # ==============================================================

  test "missing Active Directory roles deny application management" do
    as_roles(nil) do
      get admin_portal_applications_path,
          headers: html_headers

      assert_redirected_to new_user_session_path
    end
  end

  test "empty Active Directory roles deny application management" do
    as_roles do
      get admin_portal_applications_path,
          headers: html_headers

      assert_redirected_to new_user_session_path
    end
  end

  # ==============================================================
  # UNAUTHORIZED DATABASE MODIFICATION
  # ==============================================================

  test "employee cannot create corporate application" do
    as_roles(:employee) do
      assert_no_difference "PortalApplication.count" do
        post admin_portal_applications_path,
             params: {
               portal_application: {
                 name: "Unauthorized Application",
                 description: "Must not be created",
                 url: "https://example.com",
                 active: true
               }
             },
             headers: html_headers
      end

      assert_redirected_to root_path
    end
  end

  test "auditor cannot create corporate application" do
    as_roles(:auditor) do
      assert_no_difference "PortalApplication.count" do
        post admin_portal_applications_path,
             params: {
               portal_application: {
                 name: "Unauthorized Audit Application",
                 description: "Must not be created",
                 url: "https://example.com",
                 active: true
               }
             },
             headers: html_headers
      end

      assert_redirected_to root_path
    end
  end

  test "employee cannot delete corporate application" do
    as_roles(:employee) do
      assert_no_difference "PortalApplication.count" do
        delete admin_portal_application_path(1),
               headers: html_headers
      end

      assert_redirected_to root_path
    end
  end

  # ==============================================================
  # PRIVATE TEST HELPERS
  # ==============================================================

  private

  def html_headers
    { "ACCEPT" => "text/html" }
  end

  def as_roles(*roles)
    sign_in @user

    resolved_roles =
      if roles.length == 1 && roles.first.nil?
        nil
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

  def assert_management_denied_for(role)
    as_roles(role) do
      get admin_portal_applications_path,
          headers: html_headers

      assert_redirected_to root_path
    end
  end
end
