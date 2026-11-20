
# frozen_string_literal: true

module Infrastructure
  class StaleMonitoringRunRecovery
    STALE_AFTER = 10.minutes

    def call
      InfrastructureMonitoringRun.active.find_each do |run|
        inspect_run(run)
      end
    end

    private

    def inspect_run(run)
      return unless stale?(run)

      if run.active_job_id.blank?
        warn_unverified(run, "Active Job ID is missing")
        return
      end

      job = SolidQueue::Job.find_by(
        active_job_id: run.active_job_id
      )

      unless job
        warn_unverified(run, "Solid Queue job record is missing")
        return
      end

      if execution_pending_or_claimed?(job)
        Rails.logger.info(
          "[Infrastructure] Monitoring run #{run.id} " \
          "has an active or pending Solid Queue execution"
        )
        return
      end

      if SolidQueue::FailedExecution.exists?(job_id: job.id)
        mark_failed(run, "Associated Solid Queue job failed")
        return
      end

      if job.finished_at.present?
        warn_unverified(
          run,
          "Solid Queue job finished but monitoring run remains active"
        )
        return
      end

      warn_unverified(
        run,
        "No conclusive evidence that the worker has stopped"
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Infrastructure] Recovery inspection failed: " \
        "run=#{run.id}, error=#{e.class}: #{e.message}"
      )

      raise
    end

    def stale?(run)
      reference_time =
        if run.running?
          run.heartbeat_at || run.started_at
        else
          run.created_at
        end

      return false unless reference_time

      reference_time < STALE_AFTER.ago
    end

    def execution_pending_or_claimed?(job)
      SolidQueue::ReadyExecution.exists?(job_id: job.id) ||
        SolidQueue::ScheduledExecution.exists?(job_id: job.id) ||
        SolidQueue::ClaimedExecution.exists?(job_id: job.id)
    end

    def mark_failed(run, reason)
      now = Time.current

      # Conditional update prevents repeated recovery of a
      # monitoring run that has already changed state.
      updated = InfrastructureMonitoringRun
                .where(
                  id: run.id,
                  status: run.status
                )
                .where("updated_at = ?", run.updated_at)
                .update_all(
                  status: "Failed",
                  completed_at: now,
                  error_message: reason,
                  updated_at: now
                )

      return unless updated == 1

      Rails.logger.error(
        "[Infrastructure] Monitoring run #{run.id} " \
        "recovered as Failed: #{reason}"
      )
    end

    def warn_unverified(run, reason)
      Rails.logger.warn(
        "[Infrastructure] Monitoring run #{run.id} " \
        "requires investigation: #{reason}"
      )
    end
  end
end
