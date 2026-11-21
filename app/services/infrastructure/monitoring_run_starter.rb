
# frozen_string_literal: true

module Infrastructure
  class MonitoringRunStarter
    class AlreadyRunning < StandardError; end
    class NoAssets < StandardError; end
    class EnqueueFailed < StandardError; end
    class JobIdentityPersistenceFailed < StandardError; end

    def call
      # --------------------------------------------------------
      # 1. Identify eligible infrastructure assets
      # --------------------------------------------------------

      asset_ids = InfrastructureAsset
                  .where.not(status: "Retired")
                  .order(:id)
                  .pluck(:id)

      raise NoAssets, "No eligible assets to monitor" if asset_ids.empty?

      # --------------------------------------------------------
      # 2. Create the monitoring run
      # --------------------------------------------------------

      run = create_monitoring_run!(asset_ids.size)

      # --------------------------------------------------------
      # 3. Enqueue the connectivity batch job
      # --------------------------------------------------------

      begin
        job = Infrastructure::ConnectivityBatchJob.perform_later(
          run.id,
          asset_ids
        )

        raise EnqueueFailed, "Job was not enqueued" unless job

      rescue StandardError => e
        Rails.logger.error(
          "[Infrastructure] Monitoring enqueue failed: " \
          "run=#{run.id}, error=#{e.class}: #{e.message}"
        )

        fail_queued_run(
          run,
          "Job enqueue failed: #{e.class}"
        )

        raise EnqueueFailed, "Unable to enqueue monitoring job"
      end

      # --------------------------------------------------------
      # 4. Persist the Active Job UUID
      #
      # The worker may already be Running or Completed.
      #
      # Use a conditional database update to avoid model
      # validations and prevent replacing another job ID.
      # --------------------------------------------------------

      begin
        now = Time.current

        updated = InfrastructureMonitoringRun
                  .where(id: run.id, active_job_id: nil)
                  .update_all(
                    active_job_id: job.job_id,
                    updated_at: now
                  )

        if updated == 0
          current_job_id = InfrastructureMonitoringRun
                           .where(id: run.id)
                           .pick(:active_job_id)

          unless current_job_id == job.job_id
            raise JobIdentityPersistenceFailed,
                  "Monitoring run #{run.id} has a different " \
                  "or unavailable job identity"
          end
        end

        run.reload

      rescue StandardError => e
        Rails.logger.error(
          "[Infrastructure] Job identity persistence failed: " \
          "run=#{run.id}, " \
          "active_job_id=#{job.job_id}, " \
          "error=#{e.class}: #{e.message}"
        )

        raise JobIdentityPersistenceFailed,
              "Monitoring job was enqueued, but its identity " \
              "could not be persisted for run #{run.id}"
      end

      # --------------------------------------------------------
      # 5. Log successful scheduling
      # --------------------------------------------------------

      Rails.logger.info(
        "[Infrastructure] Monitoring run #{run.id} queued " \
        "for #{asset_ids.size} assets, " \
        "active_job_id=#{job.job_id}, " \
        "status=#{run.status}"
      )

      run
    end

    private

    # --------------------------------------------------------
    # Create a monitoring run with database-level protection
    # against overlapping Queued or Running runs.
    # --------------------------------------------------------

    def create_monitoring_run!(total_assets)
      InfrastructureMonitoringRun.create!(
        status: "Queued",
        total_assets: total_assets
      )

    rescue ActiveRecord::RecordNotUnique
      raise AlreadyRunning,
            "An infrastructure monitoring run is already active"
    end

    # --------------------------------------------------------
    # Mark a run Failed only while it remains Queued.
    # --------------------------------------------------------

    def fail_queued_run(run, reason)
      now = Time.current

      InfrastructureMonitoringRun
        .where(id: run.id, status: "Queued")
        .update_all(
          status: "Failed",
          completed_at: now,
          error_message: reason.truncate(2000),
          updated_at: now
        )
    end
  end
end
