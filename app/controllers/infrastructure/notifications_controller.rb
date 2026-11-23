
# frozen_string_literal: true

# ==============================================================
# HERGA CORPORATE PORTAL
# Infrastructure Notification Centre
#
# Phase 2D.8.4.3.3
# Notification Processing Diagnostics & Failure Investigation
#
# Responsibilities:
# - Administrator-only access
# - Delivery status filtering
# - Operational attention filtering
# - Notification history and pagination
# - Notification audit details
# - Solid Queue processing health
# - Notification-specific job diagnostics
#
# All diagnostic operations are read-only.
# ==============================================================

module Infrastructure
  class NotificationsController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) }
    before_action :set_notification, only: :show

    PER_PAGE = 25

    ATTENTION_THRESHOLD = 30.minutes
    RECENT_ACCEPTANCE_WINDOW = 24.hours

    ATTENTION_FILTERS = {
      "unknown" => "Unknown Outcomes",
      "stale_sending" => "Stale Sending",
      "old_pending" => "Old Pending",
      "recent_accepted" => "Accepted - Last 24 Hours"
    }.freeze

    # ==========================================================
    # INDEX
    # ==========================================================

    def index
      @enabled =
        Infrastructure::NotificationSettings.enabled?

      @activation_time =
        Infrastructure::NotificationSettings.activation_time

      @statuses = InfrastructureNotification::STATUSES
      @events = InfrastructureNotification::EVENTS

      @status_filter = params[:status].to_s
      @event_filter = params[:event_type].to_s

      @search = params[:q].to_s.strip.first(100)

      requested_attention = params[:attention].to_s

      @attention_filter =
        if ATTENTION_FILTERS.key?(requested_attention)
          requested_attention
        else
          ""
        end

      @attention_label =
        ATTENTION_FILTERS[@attention_filter]

      @now = Time.current

      load_operational_attention
      load_notifications
      load_notification_queue_health
      load_notification_job_diagnostics
    end

    # ==========================================================
    # SHOW
    # ==========================================================

    def show
      @attempts =
        @notification
          .infrastructure_notification_attempts
          .order(
            attempted_at: :desc,
            id: :desc
          )

      @source =
        case @notification.source_type

        when "InfrastructureIncident"
          InfrastructureIncident.find_by(
            id: @notification.source_id
          )

        when "InfrastructureAvailabilityAlert"
          InfrastructureAvailabilityAlert.find_by(
            id: @notification.source_id
          )

        when "InfrastructureAsset"
          InfrastructureAsset.find_by(
            id: @notification.source_id
          )

        end

      @asset =
        if @source.is_a?(InfrastructureAsset)
          @source
        else
          @source&.infrastructure_asset
        end
    end

    private

    # ==========================================================
    # NOTIFICATION LOOKUP
    # ==========================================================

    def set_notification
      @notification =
        InfrastructureNotification.find(params[:id])
    end

    # ==========================================================
    # OPERATIONAL ATTENTION SCOPES
    # ==========================================================

    def attention_scope(filter)
      notifications = InfrastructureNotification

      case filter

      when "unknown"
        notifications.where(
          status: "Unknown"
        )

      when "stale_sending"
        notifications
          .where(status: "Sending")
          .where(
            "last_attempt_at <= ?",
            @now - ATTENTION_THRESHOLD
          )

      when "old_pending"
        notifications
          .where(status: "Pending")
          .where(
            "occurred_at <= ?",
            @now - ATTENTION_THRESHOLD
          )

      when "recent_accepted"
        notifications
          .where(status: "Accepted")
          .where(
            accepted_at:
              (@now - RECENT_ACCEPTANCE_WINDOW)..@now
          )

      else
        notifications.all
      end
    end

    # ==========================================================
    # DELIVERY STATUS & OPERATIONAL ATTENTION
    # ==========================================================

    def load_operational_attention
      @summary =
        InfrastructureNotification.group(:status).count

      @total_notifications =
        @summary.values.sum

      @unknown_count =
        attention_scope("unknown").count

      @stale_sending_count =
        attention_scope("stale_sending").count

      @old_pending_count =
        attention_scope("old_pending").count

      @recent_accepted_count =
        attention_scope("recent_accepted").count

      @latest_attempt_at =
        InfrastructureNotificationAttempt.maximum(
          :attempted_at
        )

      @attention_required_count =
        @unknown_count +
        @stale_sending_count +
        @old_pending_count
    end

    # ==========================================================
    # NOTIFICATION HISTORY
    # ==========================================================

    def load_notifications
      scope =
        if @attention_filter.present?
          attention_scope(@attention_filter)
        else
          InfrastructureNotification.all
        end

      # Delivery status filtering

      if @statuses.include?(@status_filter)
        scope = scope.where(
          status: @status_filter
        )
      end

      # Event type filtering

      if @events.include?(@event_filter)
        scope = scope.where(
          event_type: @event_filter
        )
      end

      # Search filtering

      if @search.present?
        pattern =
          "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"

        scope = scope.where(
          "recipient ILIKE :q OR " \
          "event_key ILIKE :q OR " \
          "CAST(id AS TEXT) ILIKE :q",
          q: pattern
        )
      end

      # Pagination

      @total = scope.count

      @page = params[:page].to_i
      @page = 1 if @page < 1

      @page = [@page, 100_000].min

      @total_pages = [
        (@total.to_f / PER_PAGE).ceil,
        1
      ].max

      @page = [
        @page,
        @total_pages
      ].min

      @notifications =
        scope
          .recent
          .offset(
            (@page - 1) * PER_PAGE
          )
          .limit(PER_PAGE)
          .to_a
    end

    # ==========================================================
    # PHASE 2D.8.4.3.2
    # SOLID QUEUE PROCESSING HEALTH
    # ==========================================================

    def load_notification_queue_health
      @notification_queue_health =
        Infrastructure::NotificationQueueHealth.new.call
    end

    # ==========================================================
    # PHASE 2D.8.4.3.3
    # NOTIFICATION-SPECIFIC JOB DIAGNOSTICS
    # ==========================================================

    def load_notification_job_diagnostics
      @notification_job_diagnostics =
        Infrastructure::NotificationJobDiagnostics.new.call
    end
  end
end
