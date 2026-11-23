# frozen_string_literal: true

require "test_helper"
require "securerandom"

module Infrastructure
  class NotificationGovernanceEvidenceBundleControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { @user = User.create!(username: "evidence-#{SecureRandom.hex(8)}") }
    teardown { sign_out @user }

    test "guest cannot download evidence" do
      get infrastructure_notification_governance_evidence_bundle_path
      assert_redirected_to new_user_session_path
    end

    test "employee cannot download evidence" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        get infrastructure_notification_governance_evidence_bundle_path
        assert_redirected_to root_path
      end
    end

    test "administrator can download verifiable evidence" do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :admin) do
        get infrastructure_notification_governance_evidence_bundle_path
        assert_response :success
        assert_equal "application/gzip", response.media_type
        assert_equal 5, NotificationGovernanceEvidenceBundle.verify(response.body).fetch("sections").length
      end
    end
  end
end
