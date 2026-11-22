
# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "csv"

module Infrastructure
  class NotificationReportsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    # ==========================================================
    # TEST SETUP
    # ==========================================================

    setup do
      @user = User.create!(
        username: "reports-test-#{SecureRandom.hex(8)}"
      )
    end

    teardown do
      sign_out @user
    end

    # ==========================================================
    # 1. UNAUTHENTICATED ACCESS
    # ==========================================================

    test "unauthenticated HTML request redirects to login" do
      get infrastructure_notification_reports_path

      assert_redirected_to new_user_session_path
    end

    test "unauthenticated CSV request is rejected" do
      get infrastructure_notification_reports_path(
        format: :csv,
        type: "history"
      )

      assert_response :unauthorized
    end

    # ==========================================================
    # 2. EMPLOYEE ACCESS RESTRICTIONS
    # ==========================================================

    test "employee cannot view reports" do
      sign_in @user

      ActiveDirectoryAuthenticator.stub(
        :current_role,
        :employee
      ) do
        get infrastructure_notification_reports_path

        assert_redirected_to root_path
      end
    end

    test "employee cannot download CSV" do
      sign_in @user

      ActiveDirectoryAuthenticator.stub(
        :current_role,
        :employee
      ) do
        get infrastructure_notification_reports_path(
          format: :csv,
          type: "history"
        )

        assert_redirected_to root_path
      end
    end

    # ==========================================================
    # 3. ADMINISTRATOR REPORTING ACCESS
    # ==========================================================

    test "administrator sees reporting form" do
      as_admin do
        get infrastructure_notification_reports_path

        assert_response :success

        assert_select "h1",
                      text: /Notification Reporting/

        assert_select "select[name='period']", 1

        assert_select "select[name='type']", 1
      end
    end

    # ==========================================================
    # 4. NOTIFICATION HISTORY CSV
    # ==========================================================

    test "administrator can download history CSV" do
      as_admin do
        get infrastructure_notification_reports_path(
          format: :csv,
          type: "history"
        )

        assert_response :success

        assert_equal "text/csv", response.media_type

        assert_includes(
          response.headers.fetch("Content-Disposition"),
          "attachment"
        )

        csv = CSV.parse(response.body)

        assert_includes csv.first, "notification_id"
      end
    end

    # ==========================================================
    # 5. NOTIFICATION ATTEMPTS CSV
    # ==========================================================

    test "administrator can download attempts CSV" do
      as_admin do
        get infrastructure_notification_reports_path(
          format: :csv,
          type: "attempts"
        )

        assert_response :success

        assert_equal "text/csv", response.media_type

        csv = CSV.parse(response.body)

        assert_includes csv.first, "attempt_id"
      end
    end

    # ==========================================================
    # 6. NOTIFICATION ANALYTICS CSV
    # ==========================================================

    test "administrator can download analytics CSV" do
      as_admin do
        get infrastructure_notification_reports_path(
          format: :csv,
          type: "analytics"
        )

        assert_response :success

        assert_equal "text/csv", response.media_type

        csv = CSV.parse(response.body)

        assert_includes csv.first, "metric"
      end
    end

    # ==========================================================
    # 7. READ-ONLY INTEGRITY
    # ==========================================================

    test "CSV requests do not create notifications or attempts" do
      as_admin do
        assert_no_difference(
          -> { InfrastructureNotification.count }
        ) do
          assert_no_difference(
            -> { InfrastructureNotificationAttempt.count }
          ) do
            get infrastructure_notification_reports_path(
              format: :csv,
              type: "history"
            )

            assert_response :success
          end
        end
      end
    end

    # ==========================================================
    # PRIVATE HELPERS
    # ==========================================================

    private

    def as_admin
      sign_in @user

      ActiveDirectoryAuthenticator.stub(
        :current_role,
        :admin
      ) do
        yield
      end
    end
  end
end
