require "test_helper"

class PortalApplicationsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get portal_applications_index_url
    assert_response :success
  end
end
