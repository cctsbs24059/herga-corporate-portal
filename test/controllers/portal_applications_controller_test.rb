# frozen_string_literal: true

require "test_helper"

class PortalApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "redirects unauthenticated users to login" do
    get portal_applications_url

    assert_redirected_to new_user_session_path
  end
end