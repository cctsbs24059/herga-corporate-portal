# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
# Infrastructure Incident Management
# Phase 2E - Active Directory RBAC Hardening
# ============================================================

class InfrastructureIncidentsController < ApplicationController
  before_action :authenticate_user!

  before_action -> {
    require_portal_permission(:infrastructure_read)
  }, only: %i[index show]

  before_action -> {
    require_portal_permission(:infrastructure_manage)
  }, except: %i[index show]

  before_action :set_incident, only: %i[
    show acknowledge assign resolve
  ]

  PER_PAGE = 25

  # ----------------------------------------------------------
  # INCIDENT REGISTER
  # ----------------------------------------------------------

  def index
    @status_filter = params[:status].to_s

    @total_incidents = InfrastructureIncident.count

    @open_count =
      InfrastructureIncident.open_incidents.count

    @acknowledged_count =
      InfrastructureIncident
        .where(status: "Acknowledged")
        .count

    @resolved_count =
      InfrastructureIncident.resolved.count

    @unresolved_incident_count =
      InfrastructureIncident.unresolved.count

    @critical_incident_count =
      InfrastructureIncident
        .unresolved
        .where(severity: "Critical")
        .count

    @incidents =
      InfrastructureIncident
        .includes(:infrastructure_asset, :assigned_to)
        .recent

    if InfrastructureIncident::STATUSES.include?(@status_filter)
      @incidents =
        @incidents.where(status: @status_filter)
    end

    @incidents = @incidents.paginate(
      page: params[:page],
      per_page: PER_PAGE
    )
  end

  # ----------------------------------------------------------
  # INCIDENT DETAILS
  # ----------------------------------------------------------

  def show
    @events =
      @incident
        .infrastructure_incident_events
        .includes(:user)
        .recent

    @eligible_assignees = []
    @assignment_directory_available = true

    # Read-only users and resolved incidents do not require
    # additional directory lookups.

    return unless portal_can?(:infrastructure_manage)
    return unless @incident.unresolved?

    candidates =
      ActiveDirectory::IncidentAssignmentEligibility.candidates

    if candidates.nil?
      @assignment_directory_available = false
    else
      @eligible_assignees = candidates
    end
  end

  # ----------------------------------------------------------
  # ACKNOWLEDGE INCIDENT
  # ----------------------------------------------------------

  def acknowledge
    changed = false

    @incident.infrastructure_asset.with_lock do
      @incident.reload

      if @incident.status == "Open"
        @incident.update!(
          status: "Acknowledged",
          acknowledged_at: Time.current,
          acknowledged_by: current_user
        )

        record_event(
          "Acknowledged",
          "Incident acknowledged by #{current_user.username}"
        )

        changed = true
      end
    end

    if changed
      redirect_to infrastructure_incident_path(@incident),
                  notice: "Incident acknowledged successfully."
    else
      redirect_to infrastructure_incident_path(@incident),
                  alert: "Only open incidents can be acknowledged."
    end
  end

  # ----------------------------------------------------------
  # ASSIGN INCIDENT
  # ----------------------------------------------------------

  def assign
    assignee = User.find_by(
      id: params[:assigned_to_id]
    )

    # Never use the local administrator flag.
    # Verify the selected user's current AD permissions.

    unless assignee &&
           ActiveDirectory::IncidentAssignmentEligibility.eligible?(assignee)

      return redirect_to(
        infrastructure_incident_path(@incident),
        alert: "The selected user's assignment eligibility could not be verified."
      )
    end

    outcome = :invalid

    @incident.infrastructure_asset.with_lock do
      @incident.reload

      if @incident.unresolved?
        if @incident.assigned_to_id == assignee.id
          outcome = :unchanged
        else
          previous_assignee = @incident.assigned_to

          @incident.update!(
            assigned_to: assignee
          )

          event_type =
            previous_assignee ? "Reassigned" : "Assigned"

          details =
            if previous_assignee
              "Reassigned from #{previous_assignee.username} " \
                "to #{assignee.username} by #{current_user.username}"
            else
              "Assigned to #{assignee.username} " \
                "by #{current_user.username}"
            end

          record_event(event_type, details)

          outcome = :updated
        end
      end
    end

    case outcome
    when :updated
      redirect_to infrastructure_incident_path(@incident),
                  notice: "Incident assignment updated."

    when :unchanged
      redirect_to infrastructure_incident_path(@incident),
                  notice: "Incident is already assigned to this user."

    else
      redirect_to infrastructure_incident_path(@incident),
                  alert: "Resolved incidents cannot be reassigned."
    end
  end

  # ----------------------------------------------------------
  # MANUALLY RESOLVE INCIDENT
  # ----------------------------------------------------------

  def resolve
    resolution_note = params[:resolution_note].to_s.strip

    if resolution_note.blank?
      return redirect_to infrastructure_incident_path(@incident),
                         alert: "A resolution note is required."
    end

    changed = false

    @incident.infrastructure_asset.with_lock do
      @incident.reload

      if @incident.unresolved?
        @incident.update!(
          status: "Resolved",
          resolved_at: Time.current,
          resolved_by: current_user,
          resolution_note: resolution_note,
          resolution_reason: "Manually resolved",
          suppress_until_recovery: true
        )

        record_event(
          "Resolved",
          "Manually resolved by #{current_user.username}: #{resolution_note}"
        )

        changed = true
      end
    end

    if changed
      redirect_to infrastructure_incident_path(@incident),
                  notice: "Incident resolved successfully."
    else
      redirect_to infrastructure_incident_path(@incident),
                  alert: "Incident is already resolved."
    end
  end

  private

  # ----------------------------------------------------------
  # LOAD INCIDENT
  # ----------------------------------------------------------

  def set_incident
    @incident = InfrastructureIncident.find(params[:id])
  end

  # ----------------------------------------------------------
  # RECORD AUDIT EVENT
  # ----------------------------------------------------------

  def record_event(event_type, details)
    @incident.infrastructure_incident_events.create!(
      user: current_user,
      event_type: event_type,
      details: details
    )
  end
end