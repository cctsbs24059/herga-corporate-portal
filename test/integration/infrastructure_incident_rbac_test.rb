# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "securerandom"

class InfrastructureIncidentRbacTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  Eligibility = ActiveDirectory::IncidentAssignmentEligibility

  setup do
    @user = User.create!(
      username: "incident-actor-#{SecureRandom.hex(5)}",
      admin: false
    )

    @assignee = User.create!(
      username: "incident-assignee-#{SecureRandom.hex(5)}",
      admin: false
    )
  end

  teardown do
    sign_out @user
  end

  # ----------------------------------------------------------
  # INCIDENT READ ACCESS
  # ----------------------------------------------------------

  test "infrastructure administrator can access incident register" do
    as_roles(:infrastructure_admin) do
      get infrastructure_incidents_path

      assert_response :success
    end
  end

  test "auditor can access incident register" do
    as_roles(:auditor) do
      get infrastructure_incidents_path

      assert_response :success
    end
  end

  test "security administrator can access incident register" do
    as_roles(:security_admin) do
      get infrastructure_incidents_path

      assert_response :success
    end
  end

  test "employee cannot access incident register" do
    as_roles(:employee) do
      get infrastructure_incidents_path

      assert_redirected_to root_path
    end
  end

  # ----------------------------------------------------------
  # UNAUTHORISED MANAGEMENT REQUESTS
  # ----------------------------------------------------------

  %i[employee auditor security_admin].each do |role|

    test "#{role} cannot acknowledge incidents" do
      as_roles(role) do
        assert_no_difference "InfrastructureIncidentEvent.count" do
          patch acknowledge_infrastructure_incident_path(
            id: 999_999_999
          )
        end

        assert_redirected_to root_path
      end
    end

    test "#{role} cannot assign incidents" do
      as_roles(role) do
        assert_no_difference "InfrastructureIncidentEvent.count" do
          patch assign_infrastructure_incident_path(
            id: 999_999_999
          ), params: {
            assigned_to_id: @assignee.id
          }
        end

        assert_redirected_to root_path
      end
    end

    test "#{role} cannot resolve incidents" do
      as_roles(role) do
        assert_no_difference "InfrastructureIncidentEvent.count" do
          patch resolve_infrastructure_incident_path(
            id: 999_999_999
          ), params: {
            resolution_note: "Unauthorised resolution"
          }
        end

        assert_redirected_to root_path
      end
    end

  end

  # ----------------------------------------------------------
  # LOCAL ADMINISTRATOR FLAG MUST NOT GRANT ACCESS
  # ----------------------------------------------------------

  test "local administrator flag cannot authorise incident assignment" do
    @user.update!(admin: true)

    as_roles(:employee) do
      assert_no_difference "InfrastructureIncidentEvent.count" do
        patch assign_infrastructure_incident_path(
          id: 999_999_999
        ), params: {
          assigned_to_id: @assignee.id
        }
      end

      assert_redirected_to root_path
    end
  end

  # ----------------------------------------------------------
  # FAIL-CLOSED BEHAVIOUR
  # ----------------------------------------------------------

  test "directory failure prevents incident assignment" do
    as_roles(nil) do
      assert_no_difference "InfrastructureIncidentEvent.count" do
        patch assign_infrastructure_incident_path(
          id: 999_999_999
        ), params: {
          assigned_to_id: @assignee.id
        }
      end

      assert_redirected_to new_user_session_path
    end
  end

  test "revoked portal access prevents incident assignment" do
    as_roles([]) do
      assert_no_difference "InfrastructureIncidentEvent.count" do
        patch assign_infrastructure_incident_path(
          id: 999_999_999
        ), params: {
          assigned_to_id: @assignee.id
        }
      end

      assert_redirected_to new_user_session_path
    end
  end

  test "unauthenticated user cannot assign incidents" do
    patch assign_infrastructure_incident_path(
      id: 999_999_999
    ), params: {
      assigned_to_id: @assignee.id
    }

    assert_redirected_to new_user_session_path
  end

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