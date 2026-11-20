
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

      # Serialize recovery with connectivity-result persistence.
      # ConnectivityCheck must acquire the run lock first.
      InfrastructureMonitoringRun.transaction do
        locked_run = InfrastructureMonitoringRun
                     .lock
                     .find_by(id: run.id)

        next unless locked_run
        next unless locked_run.queued? || locked_run.running?

        # The worker may have refreshed its heartbeat while
        # recovery was waiting for the database lock.
        next unless stale?(locked_run)

        inspect_locked_run(locked_run)
      end
    rescue StandardError => e
      Rails.logger.error(
        "[Infrastructure] Recovery inspection failed: " \
        "run=#{run.id}, error=#{e.class}: #{e.message}"
      )

      raise
    end

    def inspect_locked_run(run)
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
      # Called only while holding the monitoring-run row lock.
      # Retaining the execution token provides an audit trail.
      # The Failed status revokes permission to persist results.
      return unless run.queued? || run.running?

      now = Time.current

      run.update!(
        status: "Failed",
        completed_at: now,
        error_message: reason.truncate(2000)
      )

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
