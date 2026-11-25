# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "securerandom"

# ============================================================
# HERGA CORPORATE PORTAL
# Phase 2E - RBAC Security Hardening
# Infrastructure Incident Lifecycle and Record Integrity
# ============================================================

class InfrastructureIncidentLifecycleRbacTest <
  ActionDispatch::IntegrationTest

  include Devise::Test::IntegrationHelpers

  Eligibility = ActiveDirectory::IncidentAssignmentEligibility

  # ----------------------------------------------------------
  # TEST DATA
  # ----------------------------------------------------------

  setup do
    identifier = SecureRandom.hex(6)

    @actor = User.create!(
      username: "incident-actor-#{identifier}",
      admin: false
    )

    @assignee = User.create!(
      username: "incident-assignee-#{identifier}",
      admin: false
    )

    @second_assignee = User.create!(
      username: "incident-second-#{identifier}",
      admin: false
    )

    @former_admin = User.create!(
      username: "incident-former-admin-#{identifier}",
      admin: true
    )

    @asset = InfrastructureAsset.create!(
      hostname: "RBAC-INCIDENT-#{identifier}",
      asset_type: "Windows Server",
      environment: "Test",
      status: "Active",
      source: "Manual"
    )

    @incident = InfrastructureIncident.create!(
      infrastructure_asset: @asset,
      incident_type: InfrastructureIncident::TYPE_ICMP,
      status: "Open",
      severity: "Critical",
      first_detected_at: Time.current,
      last_observed_at: Time.current,
      consecutive_failures: 3
    )

    @incident.infrastructure_incident_events.create!(
      event_type: "Created",
      details: "Incident created for RBAC lifecycle testing."
    )
  end

  teardown do
    sign_out @actor
  end

  # ==========================================================
  # SECTION 1
  # SUCCESSFUL INCIDENT ASSIGNMENT
  # ==========================================================

  test "infrastructure administrator can assign an eligible user" do
    as_roles(:infrastructure_admin) do
      with_eligible_assignee(@assignee) do

        assert_difference "InfrastructureIncidentEvent.count", 1 do
          assign_incident(@assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id

        event = latest_event

        assert_equal "Assigned", event.event_type
        assert_equal @actor.id, event.user_id
        assert_includes event.details, @assignee.username
        assert_includes event.details, @actor.username
      end
    end
  end

  test "portal administrator can assign an eligible user" do
    as_roles(:portal_admin) do
      with_eligible_assignee(@assignee) do

        assert_difference "InfrastructureIncidentEvent.count", 1 do
          assign_incident(@assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id
      end
    end
  end

  test "multi-role infrastructure administrator can assign incidents" do
    as_roles(:infrastructure_admin, :auditor) do
      with_eligible_assignee(@assignee) do

        assert_difference "InfrastructureIncidentEvent.count", 1 do
          assign_incident(@assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id
      end
    end
  end

  test "eligible assignee does not require local administrator flag" do
    assert_not @assignee.admin?

    as_roles(:infrastructure_admin) do
      with_eligible_assignee(@assignee) do

        assign_incident(@assignee)

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id

        assert_not @assignee.reload.admin?
      end
    end
  end

  # ==========================================================
  # SECTION 2
  # REASSIGNMENT AND AUDIT INTEGRITY
  # ==========================================================

  test "incident reassignment records previous and new assignees" do
    @incident.update!(assigned_to: @assignee)

    as_roles(:infrastructure_admin) do
      with_eligible_assignee(@second_assignee) do

        assert_difference "InfrastructureIncidentEvent.count", 1 do
          assign_incident(@second_assignee)
        end

        assert_redirected_to incident_path

        assert_equal @second_assignee.id,
                     @incident.reload.assigned_to_id

        event = latest_event

        assert_equal "Reassigned", event.event_type
        assert_equal @actor.id, event.user_id

        assert_includes event.details, @assignee.username
        assert_includes event.details, @second_assignee.username
        assert_includes event.details, @actor.username
      end
    end
  end

  test "duplicate assignment does not create duplicate audit events" do
    @incident.update!(assigned_to: @assignee)

    as_roles(:infrastructure_admin) do
      with_eligible_assignee(@assignee) do

        assert_no_difference "InfrastructureIncidentEvent.count" do
          assign_incident(@assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id
      end
    end
  end

  test "assignment does not modify incident status or severity" do
    original_status = @incident.status
    original_severity = @incident.severity
    original_failures = @incident.consecutive_failures

    as_roles(:infrastructure_admin) do
      with_eligible_assignee(@assignee) do

        assign_incident(@assignee)

        assert_redirected_to incident_path

        @incident.reload

        assert_equal @assignee.id, @incident.assigned_to_id
        assert_equal original_status, @incident.status
        assert_equal original_severity, @incident.severity

        assert_equal original_failures,
                     @incident.consecutive_failures
      end
    end
  end

  # ==========================================================
  # SECTION 3
  # INELIGIBLE AND REVOKED ASSIGNEES
  # ==========================================================

  test "ineligible assignee cannot replace existing assignee" do
    @incident.update!(assigned_to: @assignee)

    as_roles(:infrastructure_admin) do
      Eligibility.stub(:eligible?, false) do

        assert_incident_unchanged do
          assign_incident(@second_assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id
      end
    end
  end

  test "stale local administrator flag cannot grant assignment eligibility" do
    assert @former_admin.admin?

    as_roles(:portal_admin) do
      Eligibility.stub(:eligible?, false) do

        assert_incident_unchanged do
          assign_incident(@former_admin)
        end

        assert_redirected_to incident_path
        assert_nil @incident.reload.assigned_to_id
      end
    end
  end

  test "assignment eligibility is revalidated on submission" do
    as_roles(:infrastructure_admin) do

      Eligibility.stub(:candidates, [@assignee]) do
        get incident_path

        assert_response :success

        assert_select(
          "#incident-assignment-form option[value='#{@assignee.id}']",
          count: 1
        )
      end

      # Simulate eligibility being revoked after the form
      # was rendered but before the assignment was submitted.

      Eligibility.stub(:eligible?, false) do

        assert_incident_unchanged do
          assign_incident(@assignee)
        end

        assert_redirected_to incident_path
        assert_nil @incident.reload.assigned_to_id
      end
    end
  end

  test "missing assignee identifier cannot modify incident" do
    as_roles(:infrastructure_admin) do

      assert_incident_unchanged do
        patch assign_infrastructure_incident_path(@incident),
              params: { assigned_to_id: "" }
      end

      assert_redirected_to incident_path
      assert_nil @incident.reload.assigned_to_id
    end
  end

  test "nonexistent assignee cannot modify incident" do
    as_roles(:infrastructure_admin) do

      assert_incident_unchanged do
        patch assign_infrastructure_incident_path(@incident),
              params: { assigned_to_id: -1 }
      end

      assert_redirected_to incident_path
      assert_nil @incident.reload.assigned_to_id
    end
  end

  # ==========================================================
  # SECTION 4
  # FAIL-CLOSED DIRECTORY BEHAVIOUR
  # ==========================================================

  test "assignee directory verification failure preserves assignment" do
    @incident.update!(assigned_to: @assignee)

    as_roles(:infrastructure_admin) do

      # The eligibility service returns false when live
      # directory verification cannot be completed.

      Eligibility.stub(:eligible?, false) do

        assert_incident_unchanged do
          assign_incident(@second_assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id
      end
    end
  end

  test "actor directory failure prevents existing incident modification" do
    @incident.update!(assigned_to: @assignee)

    as_roles(nil) do

      assert_incident_unchanged do
        assign_incident(@second_assignee)
      end

      assert_redirected_to new_user_session_path
    end
  end

  test "revoked actor access prevents existing incident modification" do
    @incident.update!(assigned_to: @assignee)

    as_roles([]) do

      assert_incident_unchanged do
        assign_incident(@second_assignee)
      end

      assert_redirected_to new_user_session_path
    end
  end

  # ==========================================================
  # SECTION 5
  # UNAUTHORISED MANAGEMENT OPERATIONS
  # ==========================================================

  %i[employee auditor security_admin].each do |role|

    test "#{role} cannot assign an existing incident" do
      as_roles(role) do

        assert_incident_unchanged do
          assign_incident(@assignee)
        end

        assert_redirected_to root_path
      end
    end

    test "#{role} cannot acknowledge an existing incident" do
      as_roles(role) do

        assert_incident_unchanged do
          patch acknowledge_infrastructure_incident_path(
            @incident
          )
        end

        assert_redirected_to root_path
      end
    end

    test "#{role} cannot resolve an existing incident" do
      as_roles(role) do

        assert_incident_unchanged do
          patch resolve_infrastructure_incident_path(@incident),
                params: {
                  resolution_note: "Unauthorised resolution"
                }
        end

        assert_redirected_to root_path
      end
    end

  end

  # ==========================================================
  # SECTION 6
  # INCIDENT ACKNOWLEDGEMENT
  # ==========================================================

  test "infrastructure administrator can acknowledge open incident" do
    as_roles(:infrastructure_admin) do

      assert_difference "InfrastructureIncidentEvent.count", 1 do
        patch acknowledge_infrastructure_incident_path(
          @incident
        )
      end

      assert_redirected_to incident_path

      @incident.reload

      assert_equal "Acknowledged", @incident.status
      assert_equal @actor.id, @incident.acknowledged_by_id
      assert_not_nil @incident.acknowledged_at

      event = latest_event

      assert_equal "Acknowledged", event.event_type
      assert_equal @actor.id, event.user_id
      assert_includes event.details, @actor.username
    end
  end

  test "duplicate acknowledgement does not create another event" do
    @incident.update!(
      status: "Acknowledged",
      acknowledged_by: @actor,
      acknowledged_at: Time.current
    )

    as_roles(:infrastructure_admin) do

      assert_incident_unchanged do
        patch acknowledge_infrastructure_incident_path(
          @incident
        )
      end

      assert_redirected_to incident_path
    end
  end

  # ==========================================================
  # SECTION 7
  # INCIDENT RESOLUTION
  # ==========================================================

  test "infrastructure administrator can manually resolve incident" do
    note = "Connectivity issue investigated and documented."

    as_roles(:infrastructure_admin) do

      assert_difference "InfrastructureIncidentEvent.count", 1 do
        patch resolve_infrastructure_incident_path(@incident),
              params: { resolution_note: note }
      end

      assert_redirected_to incident_path

      @incident.reload

      assert_equal "Resolved", @incident.status
      assert_equal @actor.id, @incident.resolved_by_id
      assert_not_nil @incident.resolved_at

      assert_equal note, @incident.resolution_note

      assert_equal "Manually resolved",
                   @incident.resolution_reason

      assert @incident.suppress_until_recovery?

      event = latest_event

      assert_equal "Resolved", event.event_type
      assert_equal @actor.id, event.user_id
      assert_includes event.details, note
    end
  end

  test "manual resolution requires a resolution note" do
    as_roles(:infrastructure_admin) do

      assert_incident_unchanged do
        patch resolve_infrastructure_incident_path(@incident),
              params: { resolution_note: "   " }
      end

      assert_redirected_to incident_path
      assert_equal "Open", @incident.reload.status
    end
  end

  test "resolved incident cannot be reassigned" do
    mark_resolved

    @incident.update!(assigned_to: @assignee)

    as_roles(:infrastructure_admin) do
      with_eligible_assignee(@second_assignee) do

        assert_incident_unchanged do
          assign_incident(@second_assignee)
        end

        assert_redirected_to incident_path

        assert_equal @assignee.id,
                     @incident.reload.assigned_to_id
      end
    end
  end

  test "resolved incident cannot be acknowledged" do
    mark_resolved

    as_roles(:infrastructure_admin) do

      assert_incident_unchanged do
        patch acknowledge_infrastructure_incident_path(
          @incident
        )
      end

      assert_redirected_to incident_path
    end
  end

  test "resolved incident cannot be resolved again" do
    mark_resolved

    as_roles(:infrastructure_admin) do

      assert_incident_unchanged do
        patch resolve_infrastructure_incident_path(@incident),
              params: {
                resolution_note: "Second resolution attempt"
              }
      end

      assert_redirected_to incident_path
    end
  end

  # ==========================================================
  # SECTION 8
  # PERMISSION-AWARE USER INTERFACE
  # ==========================================================

  test "infrastructure administrator sees management controls" do
    as_roles(:infrastructure_admin) do
      Eligibility.stub(:candidates, [@assignee]) do

        get incident_path

        assert_response :success

        assert_select "#acknowledge-incident-button", count: 1
        assert_select "#incident-assignment-form", count: 1
        assert_select "#incident-resolution-form", count: 1
        assert_select "#incident-read-only", count: 0

        assert_select(
          "#incident-assignment-form option[value='#{@assignee.id}']",
          count: 1
        )

        assert_select(
          "#incident-assignment-form option[value='#{@former_admin.id}']",
          count: 0
        )
      end
    end
  end

  %i[auditor security_admin].each do |role|

    test "#{role} sees read-only incident details" do
      as_roles(role) do

        forbidden_lookup = lambda do
          flunk "Read-only user triggered candidate directory lookup"
        end

        Eligibility.stub(:candidates, forbidden_lookup) do

          get incident_path

          assert_response :success

          assert_select "#incident-read-only", count: 1
          assert_select "#acknowledge-incident-button", count: 0
          assert_select "#incident-assignment-form", count: 0
          assert_select "#incident-resolution-form", count: 0
        end
      end
    end

  end

  test "employee cannot view incident details" do
    as_roles(:employee) do

      forbidden_lookup = lambda do
        flunk "Unauthorised user triggered candidate directory lookup"
      end

      Eligibility.stub(:candidates, forbidden_lookup) do
        get incident_path

        assert_redirected_to root_path
      end
    end
  end

  test "directory failure hides assignment form" do
    as_roles(:infrastructure_admin) do
      Eligibility.stub(:candidates, nil) do

        get incident_path

        assert_response :success

        assert_select "#assignment-directory-unavailable", count: 1
        assert_select "#incident-assignment-form", count: 0

        # Actor authorisation remains valid. Only assignee
        # candidate verification has failed.

        assert_select "#acknowledge-incident-button", count: 1
        assert_select "#incident-resolution-form", count: 1
      end
    end
  end

  test "empty eligible candidate list hides assignment form" do
    as_roles(:infrastructure_admin) do
      Eligibility.stub(:candidates, []) do

        get incident_path

        assert_response :success

        assert_select "#no-eligible-assignees", count: 1
        assert_select "#incident-assignment-form", count: 0
        assert_select "#assignment-directory-unavailable", count: 0
      end
    end
  end

  test "resolved incident hides management forms and skips candidate lookup" do
    mark_resolved

    as_roles(:infrastructure_admin) do

      forbidden_lookup = lambda do
        flunk "Resolved incident triggered candidate directory lookup"
      end

      Eligibility.stub(:candidates, forbidden_lookup) do

        get incident_path

        assert_response :success

        assert_select "#acknowledge-incident-button", count: 0
        assert_select "#incident-assignment-form", count: 0
        assert_select "#incident-resolution-form", count: 0
      end
    end
  end

  # ==========================================================
  # TEST HELPERS
  # ==========================================================

  private

  def incident_path
    infrastructure_incident_path(@incident)
  end

  def assign_incident(user)
    patch assign_infrastructure_incident_path(@incident),
          params: { assigned_to_id: user.id }
  end

  def latest_event
    @incident.infrastructure_incident_events.recent.first
  end

  def mark_resolved
    @incident.update!(
      status: "Resolved",
      resolved_at: Time.current,
      resolved_by: @actor,
      resolution_note: "Resolved during test setup.",
      resolution_reason: "Manually resolved",
      suppress_until_recovery: true
    )
  end

  # ----------------------------------------------------------
  # Verify that a rejected request cannot modify any incident
  # attributes or existing incident audit records.
  # ----------------------------------------------------------

  def assert_incident_unchanged
    original_attributes = @incident.reload.attributes.deep_dup

    original_events =
      @incident.infrastructure_incident_events
               .order(:id)
               .map(&:attributes)
               .deep_dup

    assert_no_difference "InfrastructureIncidentEvent.count" do
      yield
    end

    assert_equal original_attributes,
                 @incident.reload.attributes

    assert_equal(
      original_events,
      @incident.infrastructure_incident_events
               .reload
               .order(:id)
               .map(&:attributes)
    )
  end

  # ----------------------------------------------------------
  # Verify that the controller checks the selected candidate.
  # ----------------------------------------------------------

  def with_eligible_assignee(expected_user)
    verifier = lambda do |actual_user|
      assert_equal expected_user.id, actual_user.id
      true
    end

    Eligibility.stub(:eligible?, verifier) do
      yield
    end
  end

  # ----------------------------------------------------------
  # Simulate live AD roles for the authenticated actor.
  # ----------------------------------------------------------

  def as_roles(*roles)
    sign_in @actor

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