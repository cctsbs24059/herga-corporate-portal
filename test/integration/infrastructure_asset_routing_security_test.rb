# frozen_string_literal: true

require "test_helper"

class InfrastructureAssetRoutingSecurityTest < ActionDispatch::IntegrationTest
  test "permanent asset deletion is not routable" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/infrastructure_assets/1", method: :delete)
    end
  end

  test "asset retirement remains routable" do
    assert_routing({ method: :patch, path: "/infrastructure_assets/1/retire" },
                   { controller: "infrastructure_assets", action: "retire", id: "1" })
  end
end
