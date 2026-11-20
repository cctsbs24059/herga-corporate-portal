# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects unauthenticated users to login" do
    get dashboard_url

    assert_redirected_to new_user_session_path
  end
end