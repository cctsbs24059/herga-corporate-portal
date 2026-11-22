# frozen_string_literal: true

module Infrastructure
  class SolidQueueHealth
    DEFAULT_HEARTBEAT_SECONDS = 120
    DEFAULT_ASSESSMENT_STALE_HOURS = 2
    DEFAULT_RECENT_FAILURE_HOURS = 24
    AVAILABILITY_TASK = "infrastructure_availability_assessment"

    def call
      now = Time.current
      heartbeat_seconds = positive_integer("HERGA_QUEUE_HEARTBEAT_STALE_SECONDS", DEFAULT_HEARTBEAT_SECONDS)
      stale_hours = positive_integer("HERGA_AVAILABILITY_ASSESSMENT_STALE_HOURS", DEFAULT_ASSESSMENT_STALE_HOURS)
      failure_hours = positive_integer("HERGA_QUEUE_RECENT_FAILURE_HOURS", DEFAULT_RECENT_FAILURE_HOURS)
      failure_cutoff = now - failure_hours.hours

      processes = SolidQueue::Process.order(:kind, :id).map do |process|
        heartbeat = process.last_heartbeat_at
        {
          kind: process.kind,
          name: process.name,
          last_heartbeat_at: heartbeat,
          healthy: heartbeat.present? && heartbeat >= now - heartbeat_seconds
        }
      end

      scheduler_healthy = processes.any? { |process| process[:kind] == "Scheduler" && process[:healthy] }
      worker_healthy = processes.any? { |process| process[:kind] == "Worker" && process[:healthy] }

      latest_assessment = InfrastructureAvailabilityAssessment.maximum(:period_end)
      assessment_stale = latest_assessment.nil? || latest_assessment < now - stale_hours.hours

      failed_count = SolidQueue::FailedExecution.count
      recent_failed_count = SolidQueue::FailedExecution.where(created_at: failure_cutoff..now).count
      historical_failed_count = failed_count - recent_failed_count
      pending_count = SolidQueue::ReadyExecution.count
      running_count = SolidQueue::ClaimedExecution.count
      scheduled_count = SolidQueue::Job.where(finished_at: nil).where("scheduled_at > ?", now).count

      recurring_tasks = SolidQueue::RecurringTask.order(:key).map do |task|
        {
          key: task.key,
          schedule: task.schedule,
          last_enqueued_at: SolidQueue::RecurringExecution.where(task_key: task.key).maximum(:run_at)
        }
      end
      availability_task_registered = recurring_tasks.any? { |task| task[:key] == AVAILABILITY_TASK }

      status = if !scheduler_healthy || !worker_healthy
                 "Unavailable"
               elsif recent_failed_count.positive? || assessment_stale || !availability_task_registered
                 "Degraded"
               else
                 "Healthy"
               end

      {
        status: status,
        checked_at: now,
        processes: processes,
        scheduler_healthy: scheduler_healthy,
        worker_healthy: worker_healthy,
        failed_count: failed_count,
        recent_failed_count: recent_failed_count,
        historical_failed_count: historical_failed_count,
        recent_failure_hours: failure_hours,
        pending_count: pending_count,
        running_count: running_count,
        scheduled_count: scheduled_count,
        latest_assessment_period_end: latest_assessment,
        assessment_stale: assessment_stale,
        recurring_tasks: recurring_tasks,
        recent_failures: SolidQueue::FailedExecution.includes(:job)
                          .where(created_at: failure_cutoff..now)
                          .order(created_at: :desc).limit(5).map do |failure|
          {
            job_class: failure.job&.class_name || "Unknown",
            failed_at: failure.created_at,
            error: failure.error.to_s.truncate(300)
          }
        end
      }
    end

    private

    def positive_integer(name, default)
      value = Integer(ENV.fetch(name, default))
      value.positive? ? value : default
    rescue ArgumentError, TypeError
      default
    end
  end
end
