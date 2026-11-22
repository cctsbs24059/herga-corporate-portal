# frozen_string_literal: true

module Infrastructure
  class MonitoringController < ApplicationController
    before_action :require_portal_administrator

    RECENT_RUN_LIMIT = 10
    RECENT_INCIDENT_LIMIT = 8
    RECENT_AVAILABILITY_ALERT_LIMIT = 8

    def index
      load_asset_statistics
      load_connectivity_statistics
      load_monitoring_statistics
      load_incident_statistics
      load_availability_alert_statistics
      load_availability_assessment_statistics
      load_solid_queue_health
      load_configuration
    end

    private

    # ----------------------------------------------------------
    # Infrastructure asset statistics
    # ----------------------------------------------------------

    def load_asset_statistics
      @total_assets = InfrastructureAsset.count

      @retired_assets = InfrastructureAsset
                        .where(status: "Retired")
                        .count

      @eligible_assets = InfrastructureAsset
                         .where.not(status: "Retired")
                         .count

      @active_assets = InfrastructureAsset
                       .where(status: "Active")
                       .count

      @maintenance_assets = InfrastructureAsset
                            .where(status: "Maintenance")
                            .count

      @directory_assets = InfrastructureAsset
                          .directory_assets
                          .count

      @manual_assets = InfrastructureAsset
                       .manual_assets
                       .count
    end

    # ----------------------------------------------------------
    # Connectivity statistics
    # Retired assets excluded from operational metrics.
    # ----------------------------------------------------------

    def load_connectivity_statistics
      eligible = InfrastructureAsset
                 .where.not(status: "Retired")

      @reachable_assets = eligible
                          .where(icmp_status: "Reachable")
                          .count

      @unreachable_assets = eligible
                            .where(icmp_status: "Unreachable")
                            .count

      @not_checked_assets = eligible
                            .where(last_connectivity_check_at: nil)
                            .count

      @unknown_assets = eligible
                        .where.not(
                          icmp_status: [
                            "Reachable",
                            "Unreachable"
                          ]
                        )
                        .count

      @last_connectivity_check = eligible
                                 .maximum(
                                   :last_connectivity_check_at
                                 )

      @reachability_percentage =
        if @eligible_assets.positive?
          (
            @reachable_assets.to_f /
            @eligible_assets * 100
          ).round(1)
        else
          0.0
        end

      @historical_check_count =
        InfrastructureConnectivityResult.count
    end

    # ----------------------------------------------------------
    # Monitoring execution statistics
    # ----------------------------------------------------------

    def load_monitoring_statistics
      @active_monitoring_run =
        InfrastructureMonitoringRun
          .active
          .recent
          .first

      @last_monitoring_run =
        InfrastructureMonitoringRun
          .recent
          .first

      @last_completed_monitoring_run =
        InfrastructureMonitoringRun
          .where(status: "Completed")
          .recent
          .first

      @recent_monitoring_runs =
        InfrastructureMonitoringRun
          .recent
          .limit(RECENT_RUN_LIMIT)

      @total_monitoring_runs =
        InfrastructureMonitoringRun.count

      @completed_monitoring_runs =
        InfrastructureMonitoringRun
          .where(status: "Completed")
          .count

      @failed_monitoring_runs =
        InfrastructureMonitoringRun
          .where(status: "Failed")
          .count

      @running_monitoring_runs =
        InfrastructureMonitoringRun
          .where(status: "Running")
          .count

      @queued_monitoring_runs =
        InfrastructureMonitoringRun
          .where(status: "Queued")
          .count
    end

    # ----------------------------------------------------------
    # Infrastructure incident statistics
    # ----------------------------------------------------------

    def load_incident_statistics
      @total_incidents = InfrastructureIncident.count

      @open_incidents =
        InfrastructureIncident
          .open_incidents
          .count

      @acknowledged_incidents =
        InfrastructureIncident
          .where(status: "Acknowledged")
          .count

      @resolved_incidents =
        InfrastructureIncident
          .resolved
          .count

      @unresolved_incidents =
        InfrastructureIncident
          .unresolved
          .count

      @critical_incidents =
        InfrastructureIncident
          .unresolved
          .where(severity: "Critical")
          .count

      @recent_incidents =
        InfrastructureIncident
          .unresolved
          .includes(:infrastructure_asset)
          .recent
          .limit(RECENT_INCIDENT_LIMIT)
    end

    # ----------------------------------------------------------
    # Phase 2D.8.2.7
    # Infrastructure availability alert statistics
    # ----------------------------------------------------------

    def load_availability_alert_statistics
      alerts = InfrastructureAvailabilityAlert

      @total_availability_alerts =
        alerts.count

      @active_availability_alerts =
        alerts.where(status: "Active").count

      @acknowledged_availability_alerts =
        alerts.where(status: "Acknowledged").count

      @cleared_availability_alerts =
        alerts.where(status: "Cleared").count

      @unresolved_availability_alerts =
        alerts
          .where(status: %w[Active Acknowledged])
          .count

      @recent_availability_alerts =
        alerts
          .includes(:infrastructure_asset)
          .where(status: %w[Active Acknowledged])
          .order(last_observed_at: :desc, id: :desc)
          .limit(RECENT_AVAILABILITY_ALERT_LIMIT)

      # --------------------------------------------------------
      # Dashboard template compatibility
      #
      # These variable names are used by the existing
      # app/views/infrastructure/monitoring/index.html.erb
      # --------------------------------------------------------

      @availability_active_alert_count =
        @active_availability_alerts

      @availability_acknowledged_alert_count =
        @acknowledged_availability_alerts

      @availability_cleared_alert_count =
        @cleared_availability_alerts

      @availability_unresolved_alert_count =
        @unresolved_availability_alerts

      @availability_total_alert_count =
        @total_availability_alerts

      @availability_recent_alerts =
        @recent_availability_alerts
    end

    # ----------------------------------------------------------
    # Latest availability assessment statistics
    # ----------------------------------------------------------

    def load_availability_assessment_statistics
      @availability_latest_period_end =
        InfrastructureAvailabilityAssessment.maximum(:period_end)

      @availability_breaches = InfrastructureAvailabilityAssessment.none
      @availability_assessed_count = 0
      @availability_breach_count = 0
      @availability_meeting_count = 0
      @availability_insufficient_count = 0
      @availability_period_start = nil

      return unless @availability_latest_period_end

      assessments = InfrastructureAvailabilityAssessment.where(
        period_end: @availability_latest_period_end
      )

      @availability_assessed_count = assessments.count
      @availability_breach_count = assessments.where(assessment_status: "BelowThreshold").count
      @availability_meeting_count = assessments.where(assessment_status: "MeetsThreshold").count
      @availability_insufficient_count = assessments.where(assessment_status: "InsufficientData").count
      @availability_breaches = assessments
                               .where(assessment_status: "BelowThreshold")
                               .includes(:infrastructure_asset)
                               .order(:infrastructure_asset_id)
      @availability_period_start = assessments.minimum(:period_start)
    end

    # ----------------------------------------------------------
    # Read-only background job health
    # ----------------------------------------------------------

    def load_solid_queue_health
      @solid_queue_health = Infrastructure::SolidQueueHealth.new.call
    end

    # ----------------------------------------------------------
    # Monitoring configuration
    # ----------------------------------------------------------

    def load_configuration
      @scheduled_monitoring_enabled =
        ENV.fetch(
          "HERGA_CONNECTIVITY_MONITORING_ENABLED",
          "false"
        ) == "true"

      @automatic_recovery_enabled =
        ENV.fetch(
          "HERGA_MONITORING_RECOVERY_ENABLED",
          "false"
        ) == "true"

      @scheduled_availability_assessments_enabled =
        ENV.fetch(
          "HERGA_AVAILABILITY_ASSESSMENTS_ENABLED",
          "false"
        ) == "true"

      @availability_threshold_percentage =
        ENV.fetch(
          "HERGA_AVAILABILITY_THRESHOLD_PERCENT",
          "99"
        ).to_f

      @availability_period_hours =
        ENV.fetch(
          "HERGA_AVAILABILITY_PERIOD_HOURS",
          "24"
        ).to_i

      @scheduled_availability_enabled = @scheduled_availability_assessments_enabled
      @availability_threshold = @availability_threshold_percentage
      @availability_schedule_interval = "Every hour"

      @monitoring_interval_minutes = 15
    end
  end
end
