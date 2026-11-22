# frozen_string_literal: true

require 'test_helper'
require 'securerandom'

module Infrastructure
  class NotificationJobFailuresControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(username: "failure-test-#{SecureRandom.hex(6)}")
    end

    teardown do
      sign_out @user
    end

    test 'unauthenticated access to failure history redirects to login' do
      get infrastructure_notification_job_failures_path
      assert_redirected_to new_user_session_path
    end

    test 'unauthenticated access to failure details redirects to login' do
      get infrastructure_notification_job_failure_path(1)
      assert_redirected_to new_user_session_path
    end

    test 'employee cannot access failure history' do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        get infrastructure_notification_job_failures_path
        assert_redirected_to root_path
      end
    end

    test 'employee cannot access failure details' do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :employee) do
        get infrastructure_notification_job_failure_path(1)
        assert_redirected_to root_path
      end
    end

    test 'administrator can access failure history' do
      sign_in @user
      ActiveDirectoryAuthenticator.stub(:current_role, :admin) do
        get infrastructure_notification_job_failures_path
        assert_response :success
        assert_select 'h1', text: /Notification Failure Investigation/
      end
    end
  end
end
