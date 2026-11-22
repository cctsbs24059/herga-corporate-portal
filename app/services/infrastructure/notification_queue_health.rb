
# frozen_string_literal: true

module Infrastructure
  class NotificationQueueHealth
    RECONCILIATION_TASK =
      "infrastructure_notification_reconciliation"

    def call
      health = Infrastructure::SolidQueueHealth.new.call

      processes = health.fetch(:processes, [])
      workers = processes.select { |process| process[:kind] == "Worker" }

      reconciliation = health.fetch(:recurring_tasks, []).find do |task|
        task[:key] == RECONCILIATION_TASK
      end

      {
        available: true,
        checked_at: health[:checked_at],
        overall_status: health[:status],
        worker_healthy: health[:worker_healthy],
        scheduler_healthy: health[:scheduler_healthy],
        worker_count: workers.count,
        healthy_worker_count: workers.count { |worker| worker[:healthy] },
        workers: workers,
        pending_jobs: health[:pending_count],
        running_jobs: health[:running_count],
        scheduled_jobs: health[:scheduled_count],
        failed_jobs: health[:failed_count],
        recent_failed_jobs: health[:recent_failed_count],
        recent_failure_hours: health[:recent_failure_hours],
        recent_failures: health[:recent_failures],
        reconciliation_registered: reconciliation.present?,
        reconciliation_schedule: reconciliation&.dig(:schedule),
        reconciliation_last_enqueued_at:
          reconciliation&.dig(:last_enqueued_at),
        error: nil
      }
    rescue ActiveRecord::ActiveRecordError,
           ActiveRecord::ConnectionNotEstablished,
           PG::Error => e
      Rails.logger.error(
        "[NotificationQueueHealth] #{e.class}: #{e.message}"
      )

      {
        available: false,
        checked_at: Time.current,
        overall_status: "Unavailable",
        worker_healthy: false,
        scheduler_healthy: false,
        worker_count: 0,
        healthy_worker_count: 0,
        workers: [],
        pending_jobs: nil,
        running_jobs: nil,
        scheduled_jobs: nil,
        failed_jobs: nil,
        recent_failed_jobs: nil,
        recent_failure_hours: nil,
        recent_failures: [],
        reconciliation_registered: false,
        reconciliation_schedule: nil,
        reconciliation_last_enqueued_at: nil,
        error: "Queue health information is temporarily unavailable."
      }
    end
  end
end
