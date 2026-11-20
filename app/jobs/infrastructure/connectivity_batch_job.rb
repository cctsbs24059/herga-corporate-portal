
# frozen_string_literal: true

module Infrastructure
  class ConnectivityBatchJob < ApplicationJob
    queue_as :default

    def perform(monitoring_run_id, asset_ids)
      now = Time.current

      # Atomically claim the queued monitoring run.
      claimed = InfrastructureMonitoringRun
                .where(id: monitoring_run_id, status: "Queued")
                .update_all(
                  status: "Running",
                  started_at: now,
                  heartbeat_at: now,
                  updated_at: now
                )

      unless claimed == 1
        Rails.logger.warn(
          "[Infrastructure] Monitoring run #{monitoring_run_id} " \
          "was not queued; skipping duplicate execution"
        )
        return
      end

      run = InfrastructureMonitoringRun.find(monitoring_run_id)

      Rails.logger.info(
        "[Infrastructure] Monitoring run #{run.id} started " \
        "for #{asset_ids.size} assets"
      )

      begin
        asset_ids.each do |asset_id|
          # Refresh the heartbeat before processing an asset.
          run.update_columns(
            heartbeat_at: Time.current,
            updated_at: Time.current
          )

          asset = InfrastructureAsset.find_by(id: asset_id)

          unless asset
            run.increment!(:processed_assets)
            run.increment!(:failed_checks)

            Rails.logger.warn(
              "[Infrastructure] Asset #{asset_id} no longer exists"
            )

            next
          end

          begin
            Infrastructure::ConnectivityCheck.new(
              asset,
              monitoring_run: run
            ).call

            case asset.icmp_status
            when "Reachable"
              run.increment!(:reachable_assets)
            when "Unreachable"
              run.increment!(:unreachable_assets)
            else
              run.increment!(:unknown_assets)
            end

            Rails.logger.info(
              "[Infrastructure] Run=#{run.id}, " \
              "asset=#{asset.hostname}, " \
              "DNS=#{asset.dns_status}, " \
              "ICMP=#{asset.icmp_status}"
            )

          rescue StandardError => e
            run.increment!(:failed_checks)

            Rails.logger.error(
              "[Infrastructure] Run=#{run.id}, " \
              "asset=#{asset.hostname}, " \
              "error=#{e.class}: #{e.message}"
            )

          ensure
            run.increment!(:processed_assets)
          end
        end

        run.update!(
          status: "Completed",
          completed_at: Time.current,
          heartbeat_at: Time.current
        )

        Rails.logger.info(
          "[Infrastructure] Monitoring run #{run.id} completed: " \
          "processed=#{run.processed_assets}, " \
          "reachable=#{run.reachable_assets}, " \
          "unreachable=#{run.unreachable_assets}, " \
          "unknown=#{run.unknown_assets}, " \
          "errors=#{run.failed_checks}"
        )

      rescue StandardError => e
        Rails.logger.error(
          "[Infrastructure] Monitoring run #{run.id} failed: " \
          "#{e.class}: #{e.message}"
        )

        InfrastructureMonitoringRun
          .where(id: run.id, status: "Running")
          .update_all(
            status: "Failed",
            completed_at: Time.current,
            heartbeat_at: Time.current,
            error_message: "#{e.class}: #{e.message}".truncate(2000),
            updated_at: Time.current
          )

        raise
      end
    end
  end
end
