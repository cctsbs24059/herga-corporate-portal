
# frozen_string_literal: true

module Infrastructure
  class MonitoringController < ApplicationController
    before_action :require_portal_administrator

    RECENT_RUN_LIMIT = 10
    RECENT_INCIDENT_LIMIT = 8

    def index
      load_asset_statistics
      load_connectivity_statistics
      load_monitoring_statistics
      load_incident_statistics
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
    #
    # Retired assets are excluded from operational metrics.
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

      @monitoring_interval_minutes = 15
    end
  end
end
