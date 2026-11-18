
# frozen_string_literal: true

module Infrastructure
  class MonitoringRunStarter
    class AlreadyRunning < StandardError; end
    class NoAssets < StandardError; end
    class EnqueueFailed < StandardError; end

    def call
      asset_ids = InfrastructureAsset
                  .where.not(status: "Retired")
                  .order(:id)
                  .pluck(:id)

      raise NoAssets, "No eligible assets to monitor" if asset_ids.empty?

      run = create_monitoring_run!(asset_ids.size)

      begin
        job = Infrastructure::ConnectivityBatchJob.perform_later(
          run.id,
          asset_ids
        )

        raise EnqueueFailed, "Job was not enqueued" unless job

      rescue StandardError => e
        Rails.logger.error(
          "[Infrastructure] Monitoring enqueue failed: " \
          "#{e.class}: #{e.message}"
        )

        if run.reload.status == "Queued"
          run.update!(
            status: "Failed",
            completed_at: Time.current,
            error_message: "Job enqueue failed: #{e.class}".truncate(2000)
          )
        end

        raise EnqueueFailed, "Unable to enqueue monitoring job"
      end

      Rails.logger.info(
        "[Infrastructure] Monitoring run #{run.id} queued " \
        "for #{asset_ids.size} assets"
      )

      run
    end

    private

    def create_monitoring_run!(total_assets)
      InfrastructureMonitoringRun.create!(
        status: "Queued",
        total_assets: total_assets
      )

    rescue ActiveRecord::RecordNotUnique => e
      raise AlreadyRunning,
            "An infrastructure monitoring run is already active"
    end
  end
end
