
# frozen_string_literal: true

module Infrastructure
  class NotificationJobDiagnostics
    JOB_CLASSES = %w[
      Infrastructure::NotificationDeliveryJob
      Infrastructure::NotificationReconciliationJob
    ].freeze

    RECENT_FAILURE_LIMIT = 10
    RECENT_FAILURE_WINDOW = 24.hours

    def call
      now = Time.current
      cutoff = now - RECENT_FAILURE_WINDOW

      jobs = SolidQueue::Job.where(class_name: JOB_CLASSES)
      job_ids = jobs.select(:id)

      failures = SolidQueue::FailedExecution
        .where(job_id: job_ids)

      recent_failures = failures
        .where(created_at: cutoff..now)

      ready_count = SolidQueue::ReadyExecution
        .where(job_id: job_ids)
        .count

      running_count = SolidQueue::ClaimedExecution
        .where(job_id: job_ids)
        .count

      scheduled_count = jobs
        .where(finished_at: nil)
        .where("scheduled_at > ?", now)
        .count

      processes = SolidQueue::Process
        .where(kind: "Worker")
        .to_a

      heartbeat_seconds = positive_integer(
        ENV["HERGA_QUEUE_HEARTBEAT_STALE_SECONDS"],
        120
      )

      healthy_workers = processes.count do |process|
        process.last_heartbeat_at.present? &&
          process.last_heartbeat_at >= now - heartbeat_seconds.seconds
      end

      recent_failure_count = recent_failures.count

      status =
        if healthy_workers.zero?
          "Unavailable"
        elsif recent_failure_count.positive?
          "Degraded"
        else
          "Healthy"
        end

      {
        available: true,
        status: status,
        checked_at: now,
        total_jobs: jobs.count,
        delivery_jobs: jobs.where(
          class_name: JOB_CLASSES.first
        ).count,
        reconciliation_jobs: jobs.where(
          class_name: JOB_CLASSES.last
        ).count,
        ready_count: ready_count,
        running_count: running_count,
        scheduled_count: scheduled_count,
        total_failed_count: failures.count,
        recent_failed_count: recent_failure_count,
        healthy_workers: healthy_workers,
        recent_failures: recent_failures
          .includes(:job)
          .order(created_at: :desc, id: :desc)
          .limit(RECENT_FAILURE_LIMIT)
          .map do |failure|
            {
              id: failure.id,
              job_id: failure.job_id,
              job_class: failure.job&.class_name,
              queue_name: failure.job&.queue_name,
              failed_at: failure.created_at,
              error: failure.error.to_s.truncate(300)
            }
          end,
        error: nil
      }
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error(
        "[NotificationJobDiagnostics] #{e.class}: #{e.message}"
      )

      {
        available: false,
        status: "Unavailable",
        checked_at: Time.current,
        total_jobs: nil,
        delivery_jobs: nil,
        reconciliation_jobs: nil,
        ready_count: nil,
        running_count: nil,
        scheduled_count: nil,
        total_failed_count: nil,
        recent_failed_count: nil,
        healthy_workers: nil,
        recent_failures: [],
        error: "Notification job diagnostics are temporarily unavailable."
      }
    end

    private

    def positive_integer(value, default)
      parsed = Integer(value)
      parsed.positive? ? parsed : default
    rescue ArgumentError, TypeError
      default
    end
  end
end
