# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class NotificationHealthAssessmentTest < ActiveSupport::TestCase
    def queue
      { available: true, worker_healthy: true, scheduler_healthy: true,
        reconciliation_registered: true, overall_status: "Healthy" }
    end

    def jobs
      { available: true, healthy_workers: 1, recent_failed_count: 0, status: "Healthy" }
    end

    def assess(enabled: true, queue_health: queue, job_diagnostics: jobs)
      Infrastructure::NotificationHealthAssessment.new(
        enabled: enabled, queue_health: queue_health, job_diagnostics: job_diagnostics
      ).call
    end

    test "disabled notification service is distinct from failure" do
      result = assess(enabled: false)
      assert_equal "Disabled", result[:status]
      assert_empty result[:indicators]
    end

    test "healthy when no attention items and processing available" do
      assert_equal "Healthy", assess[:status]
    end

    test "unavailable when job diagnostics unavailable" do
      result = assess(job_diagnostics: jobs.merge(available: false))
      assert_equal "Unavailable", result[:status]
      assert result[:indicators].any? { |i| i[:key] == "processing" && i[:status] == "Unavailable" }
    end

    test "unavailable when no healthy workers" do
      assert_equal "Unavailable", assess(job_diagnostics: jobs.merge(healthy_workers: 0))[:status]
    end

    test "degraded on recent failed jobs" do
      assert_equal "Degraded", assess(job_diagnostics: jobs.merge(recent_failed_count: 1))[:status]
    end

    test "invalid environment threshold falls back safely" do
      previous = ENV["HERGA_NOTIFICATION_STALE_MINUTES"]
      ENV["HERGA_NOTIFICATION_STALE_MINUTES"] = "invalid"
      assert_equal 30, assess[:stale_minutes]
    ensure
      ENV["HERGA_NOTIFICATION_STALE_MINUTES"] = previous
    end
  end
end
