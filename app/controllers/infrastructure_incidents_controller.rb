
# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
# Phase 2D.6.4 - Infrastructure Incident Management
# ============================================================

class InfrastructureIncidentsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { require_portal_permission(:infrastructure_read) },
                only: %i[index show]

  before_action -> { require_portal_permission(:infrastructure_manage) },
                only: %i[acknowledge assign resolve]

  before_action :set_incident, only: %i[
    show acknowledge assign resolve
  ]

  PER_PAGE = 25

  # ----------------------------------------------------------
  # INCIDENT REGISTER
  # ----------------------------------------------------------

  def index
    @status_filter = params[:status].to_s

    # --------------------------------------------------------
    # Incident statistics
    # --------------------------------------------------------

    @total_incidents = InfrastructureIncident.count

    @open_count =
      InfrastructureIncident.open_incidents.count

    @acknowledged_count =
      InfrastructureIncident
        .where(status: "Acknowledged")
        .count

    @resolved_count =
      InfrastructureIncident.resolved.count

    # Includes both Open and Acknowledged incidents.
    # Required by the incident register view.
    @unresolved_incident_count =
      InfrastructureIncident.unresolved.count

    @critical_incident_count =
      InfrastructureIncident
        .unresolved
        .where(severity: "Critical")
        .count

    # --------------------------------------------------------
    # Incident filtering
    # --------------------------------------------------------

    @incidents =
      InfrastructureIncident
        .includes(:infrastructure_asset, :assigned_to)
        .recent

    if InfrastructureIncident::STATUSES.include?(@status_filter)
      @incidents =
        @incidents.where(status: @status_filter)
    end

    # --------------------------------------------------------
    # Pagination
    # --------------------------------------------------------

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

    # Assignment candidates are local administrator profiles.
    # Administrator status is refreshed during successful AD
    # login and is not a substitute for live AD authorization.

    @administrators =
      User
        .where(admin: true)
        .order(:username)
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
    administrator = User.find_by(
      id: params[:assigned_to_id],
      admin: true
    )

    unless administrator
      return redirect_to infrastructure_incident_path(@incident),
                         alert: "Select a valid administrator."
    end

    outcome = :invalid

    @incident.infrastructure_asset.with_lock do
      @incident.reload

      if @incident.unresolved?
        if @incident.assigned_to_id == administrator.id
          outcome = :unchanged
        else
          previous_assignee = @incident.assigned_to

          @incident.update!(
            assigned_to: administrator
          )

          event_type =
            previous_assignee ? "Reassigned" : "Assigned"

          details =
            if previous_assignee
              "Reassigned from #{previous_assignee.username} " \
                "to #{administrator.username} by #{current_user.username}"
            else
              "Assigned to #{administrator.username} " \
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
                  notice: "Incident is already assigned to this administrator."

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
