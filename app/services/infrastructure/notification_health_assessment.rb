# frozen_string_literal: true

module Infrastructure
  class NotificationHealthAssessment
    DEFAULT_THRESHOLD_MINUTES = 30
    DEFAULT_UNKNOWN_LIMIT = 0
    DEFAULT_RECENT_FAILURE_LIMIT = 0

    def initialize(queue_health:, job_diagnostics:, enabled:, now: Time.current)
      @queue_health = queue_health
      @job_diagnostics = job_diagnostics
      @enabled = enabled
      @now = now
    end

    def call
      return result("Disabled", []) unless @enabled

      cutoff = @now - threshold("HERGA_NOTIFICATION_STALE_MINUTES", DEFAULT_THRESHOLD_MINUTES).minutes
      unknown_count = InfrastructureNotification.where(status: "Unknown").count
      stale_sending_count = InfrastructureNotification.where(status: "Sending")
        .where("COALESCE(last_attempt_at, occurred_at, created_at) <= ?", cutoff).count
      old_pending_count = InfrastructureNotification.where(status: "Pending")
        .where("COALESCE(occurred_at, created_at) <= ?", cutoff).count

      indicators = [
        indicator("unknown", "Unknown submission outcomes", unknown_count,
          threshold("HERGA_NOTIFICATION_UNKNOWN_LIMIT", DEFAULT_UNKNOWN_LIMIT),
          "Unknown outcomes require investigation before any resend."),
        indicator("stale_sending", "Stale Sending notifications", stale_sending_count, 0,
          "Sending notifications have exceeded the age threshold."),
        indicator("old_pending", "Old Pending notifications", old_pending_count, 0,
          "Pending notifications have exceeded the age threshold.")
      ]

      if !@queue_health[:available] || !@job_diagnostics[:available]
        indicators << { key: "processing", label: "Processing diagnostics", status: "Unavailable",
          count: nil, message: "Queue or job diagnostics could not be retrieved." }
      else
        recent_failures = @job_diagnostics[:recent_failed_count].to_i
        healthy_workers = @job_diagnostics[:healthy_workers].to_i
        unhealthy = healthy_workers.zero? || !@queue_health[:worker_healthy] ||
          !@queue_health[:scheduler_healthy] || !@queue_health[:reconciliation_registered] ||
          @job_diagnostics[:status] == "Unavailable" ||
          @queue_health[:overall_status] == "Unavailable"
        indicators << { key: "processing", label: "Notification processing infrastructure",
          status: unhealthy ? "Unavailable" : "Healthy", count: healthy_workers,
          message: unhealthy ? "Workers, scheduler, or reconciliation are not healthy." : "Processing infrastructure is available." }
        indicators << indicator("failed_jobs", "Recent failed notification jobs", recent_failures,
          threshold("HERGA_NOTIFICATION_RECENT_FAILURE_LIMIT", DEFAULT_RECENT_FAILURE_LIMIT),
          "Recent failed jobs require investigation; this does not prove notification delivery failed.")
      end

      status = if indicators.any? { |item| item[:status] == "Unavailable" }
        "Unavailable"
      elsif indicators.any? { |item| item[:status] == "Degraded" }
        "Degraded"
      else
        "Healthy"
      end
      result(status, indicators)
    end

    private

    def result(status, indicators)
      { status: status, checked_at: @now, indicators: indicators,
        stale_minutes: threshold("HERGA_NOTIFICATION_STALE_MINUTES", DEFAULT_THRESHOLD_MINUTES) }
    end

    def indicator(key, label, count, limit, message)
      { key: key, label: label, count: count, limit: limit,
        status: count > limit ? "Degraded" : "Healthy", message: message }
    end

    def threshold(key, fallback)
      value = Integer(ENV.fetch(key, fallback))
      value >= 0 && value <= 100_000 ? value : fallback
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
