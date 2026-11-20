
# frozen_string_literal: true

require "securerandom"

module Infrastructure
  class ConnectivityBatchJob < ApplicationJob
    queue_as :default

    class ExecutionOwnershipLost < StandardError; end

    def perform(monitoring_run_id, asset_ids)
      execution_token = SecureRandom.uuid

      now = Time.current

      claimed = InfrastructureMonitoringRun
                .where(
                  id: monitoring_run_id,
                  status: "Queued",
                  execution_token: nil
                )
                .update_all(
                  status: "Running",
                  execution_token: execution_token,
                  started_at: now,
                  heartbeat_at: now,
                  updated_at: now
                )

      unless claimed == 1
        Rails.logger.warn(
          "[Infrastructure] Monitoring run #{monitoring_run_id} " \
          "could not be claimed; skipping execution"
        )
        return
      end

      run = InfrastructureMonitoringRun.find(monitoring_run_id)

      Rails.logger.info(
        "[Infrastructure] Monitoring run #{run.id} started, " \
        "execution_token=#{execution_token}, " \
        "assets=#{asset_ids.size}"
      )

      begin
        asset_ids.each do |asset_id|
          refresh_heartbeat!(run.id, execution_token)

          asset = InfrastructureAsset.find_by(id: asset_id)

          unless asset
            record_progress!(
              run.id,
              execution_token: execution_token,
              processed: 1,
              failed: 1
            )

            Rails.logger.warn(
              "[Infrastructure] Run=#{run.id}, " \
              "asset_id=#{asset_id} no longer exists"
            )

            next
          end

          begin
            Infrastructure::ConnectivityCheck.new(
              asset,
              monitoring_run: run,
              execution_token: execution_token
            ).call

            asset.reload

            case asset.icmp_status
            when "Reachable"
              record_progress!(
                run.id,
                execution_token: execution_token,
                processed: 1,
                reachable: 1
              )

            when "Unreachable"
              record_progress!(
                run.id,
                execution_token: execution_token,
                processed: 1,
                unreachable: 1
              )

            else
              record_progress!(
                run.id,
                execution_token: execution_token,
                processed: 1,
                unknown: 1
              )
            end

            Rails.logger.info(
              "[Infrastructure] Run=#{run.id}, " \
              "asset=#{asset.hostname}, " \
              "DNS=#{asset.dns_status}, " \
              "ICMP=#{asset.icmp_status}"
            )

          rescue ExecutionOwnershipLost
            raise

          rescue StandardError => e
            record_progress!(
              run.id,
              execution_token: execution_token,
              processed: 1,
              failed: 1
            )

            Rails.logger.error(
              "[Infrastructure] Run=#{run.id}, " \
              "asset=#{asset.hostname}, " \
              "error=#{e.class}: #{e.message}"
            )
          end
        end

        complete_run!(run.id, execution_token)

        Rails.logger.info(
          "[Infrastructure] Monitoring run #{run.id} completed"
        )

      rescue ExecutionOwnershipLost => e
        Rails.logger.warn(
          "[Infrastructure] Monitoring run #{run.id} stopped: " \
          "#{e.message}"
        )

        return

      rescue StandardError => e
        Rails.logger.error(
          "[Infrastructure] Monitoring run #{run.id} failed: " \
          "#{e.class}: #{e.message}"
        )

        fail_run!(run.id, execution_token, e)
        raise
      end
    end

    private

    def owned_run(run_id, execution_token)
      InfrastructureMonitoringRun.where(
        id: run_id,
        status: "Running",
        execution_token: execution_token
      )
    end

    def refresh_heartbeat!(run_id, execution_token)
      now = Time.current

      updated = owned_run(run_id, execution_token).update_all(
        heartbeat_at: now,
        updated_at: now
      )

      ensure_ownership!(run_id, updated)
    end

    def record_progress!(
      run_id,
      execution_token:,
      processed: 0,
      reachable: 0,
      unreachable: 0,
      unknown: 0,
      failed: 0
    )
      now = Time.current

      updated = owned_run(run_id, execution_token).update_all(
        [
          "processed_assets = processed_assets + ?, " \
          "reachable_assets = reachable_assets + ?, " \
          "unreachable_assets = unreachable_assets + ?, " \
          "unknown_assets = unknown_assets + ?, " \
          "failed_checks = failed_checks + ?, " \
          "heartbeat_at = ?, updated_at = ?",
          processed,
          reachable,
          unreachable,
          unknown,
          failed,
          now,
          now
        ]
      )

      ensure_ownership!(run_id, updated)
    end

    def complete_run!(run_id, execution_token)
      now = Time.current

      updated = owned_run(run_id, execution_token).update_all(
        status: "Completed",
        completed_at: now,
        heartbeat_at: now,
        updated_at: now
      )

      ensure_ownership!(run_id, updated)
    end

    def fail_run!(run_id, execution_token, error)
      now = Time.current

      owned_run(run_id, execution_token).update_all(
        status: "Failed",
        completed_at: now,
        heartbeat_at: now,
        error_message: "#{error.class}: #{error.message}".truncate(2000),
        updated_at: now
      )
    end

    def ensure_ownership!(run_id, affected_rows)
      return if affected_rows == 1

      raise ExecutionOwnershipLost,
            "Monitoring run #{run_id} execution ownership lost"
    end
  end
end
