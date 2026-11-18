# frozen_string_literal: true

module Infrastructure
  class HealthEvaluator
    WARNING_LATENCY_MS = 150.0
    CRITICAL_LATENCY_MS = 500.0
    CRITICAL_FAILURE_COUNT = 3
    STALE_AFTER = 45.minutes
    HISTORY_LIMIT = 10

    Result = Struct.new(:status, :reason, :consecutive_failures,
                        :latency_ms, :last_checked_at, keyword_init: true)

    def initialize(asset, now: Time.current, checks: nil)
      @asset = asset
      @now = now
      @checks = checks
    end

    def call
      return result("Not Monitored", "Asset is retired") if @asset.status == "Retired"

      checks = @checks || InfrastructureConnectivityResult
               .where(infrastructure_asset_id: @asset.id)
               .order(checked_at: :desc, id: :desc)
               .limit(HISTORY_LIMIT).to_a

      return result("Unknown", "No connectivity history available") if checks.empty?

      latest = checks.first
      if latest.checked_at < @now - STALE_AFTER
        return result("Unknown", "Monitoring data is overdue", last_checked_at: latest.checked_at)
      end

      case latest.icmp_status
      when "Reachable"
        latency = latest.icmp_response_ms
        status = if latency && latency >= CRITICAL_LATENCY_MS
                   "Critical"
                 elsif latency && latency >= WARNING_LATENCY_MS
                   "Warning"
                 else
                   "Healthy"
                 end
        reason = status == "Healthy" ? "Latest ICMP check successful" : "ICMP latency threshold exceeded"
        result(status, reason, latency_ms: latency, last_checked_at: latest.checked_at)
      when "Unreachable"
        failures = checks.take_while { |check| check.icmp_status == "Unreachable" }.size
        status = failures >= CRITICAL_FAILURE_COUNT ? "Critical" : "Warning"
        result(status, "#{failures} consecutive unsuccessful ICMP checks",
               consecutive_failures: failures, last_checked_at: latest.checked_at)
      else
        result("Unknown", latest.connectivity_error.presence || "Latest ICMP result unknown",
               last_checked_at: latest.checked_at)
      end
    end

    private

    def result(status, reason, consecutive_failures: 0, latency_ms: nil, last_checked_at: nil)
      Result.new(status: status, reason: reason, consecutive_failures: consecutive_failures,
                 latency_ms: latency_ms, last_checked_at: last_checked_at)
    end
  end
end
