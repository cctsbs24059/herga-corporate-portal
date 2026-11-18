
# frozen_string_literal: true

module Infrastructure
  class IncidentDetector
    def initialize(asset, connectivity_result:)
      @asset = asset
      @connectivity_result = connectivity_result
    end

    def call
      @asset.with_lock do
        latest = InfrastructureConnectivityResult
                 .where(infrastructure_asset_id: @asset.id)
                 .order(checked_at: :desc, id: :desc)
                 .first

        # Ignore outdated monitoring results.
        return unless latest&.id == @connectivity_result.id

        incident = InfrastructureIncident.unresolved.find_by(
          infrastructure_asset_id: @asset.id,
          incident_type: InfrastructureIncident::TYPE_ICMP
        )

        if @asset.status == "Retired"
          resolve(incident, "Asset retired", "Retired")
          return
        end

        case latest.icmp_status
        when "Reachable"
          handle_recovery(incident)

        when "Unreachable"
          handle_failure(incident, latest)

        end

        # Unknown results do not change incident state.
      end
    end

    private

    def handle_recovery(incident)
      resolve(incident, "Connectivity restored", "Recovered")

      # A successful check ends manual-resolution suppression.
      InfrastructureIncident
        .where(
          infrastructure_asset_id: @asset.id,
          incident_type: InfrastructureIncident::TYPE_ICMP,
          status: "Resolved",
          suppress_until_recovery: true
        )
        .update_all(
          suppress_until_recovery: false,
          updated_at: Time.current
        )
    end

    def handle_failure(incident, latest)
      threshold =
        Infrastructure::HealthEvaluator::CRITICAL_FAILURE_COUNT

      failures = InfrastructureConnectivityResult
                 .where(infrastructure_asset_id: @asset.id)
                 .order(checked_at: :desc, id: :desc)
                 .limit(threshold)
                 .to_a

      return unless failures.length == threshold

      return unless failures.all? do |check|
        check.icmp_status == "Unreachable"
      end

      if incident
        incident.update!(
          last_observed_at: latest.checked_at,
          consecutive_failures: incident.consecutive_failures + 1
        )
        return
      end

      # A manually resolved incident must not reopen
      # until successful connectivity has been observed.
      suppressed = InfrastructureIncident.exists?(
        infrastructure_asset_id: @asset.id,
        incident_type: InfrastructureIncident::TYPE_ICMP,
        status: "Resolved",
        suppress_until_recovery: true
      )

      return if suppressed

      new_incident = InfrastructureIncident.create!(
        infrastructure_asset: @asset,
        incident_type: InfrastructureIncident::TYPE_ICMP,
        severity: "Critical",
        status: "Open",
        description: "Three consecutive unsuccessful ICMP checks",
        first_detected_at: latest.checked_at,
        last_observed_at: latest.checked_at,
        consecutive_failures: threshold
      )

      record_event(
        new_incident,
        "Created",
        "Automatically detected after #{threshold} consecutive unsuccessful ICMP checks"
      )
    end

    def resolve(incident, reason, event_type)
      return unless incident

      incident.update!(
        status: "Resolved",
        resolved_at: Time.current,
        resolution_reason: reason,
        suppress_until_recovery: false
      )

      record_event(incident, event_type, reason)
    end

    def record_event(incident, event_type, details)
      InfrastructureIncidentEvent.create!(
        infrastructure_incident: incident,
        event_type: event_type,
        details: details
      )
    end
  end
end
