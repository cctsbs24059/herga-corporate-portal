
# frozen_string_literal: true

module Infrastructure
  class ScheduledConnectivityJob < ApplicationJob
    queue_as :default

    def perform
      # --------------------------------------------------------
      # 1. Check whether scheduled monitoring is enabled
      # --------------------------------------------------------

      unless ENV.fetch(
        "HERGA_CONNECTIVITY_MONITORING_ENABLED",
        "false"
      ) == "true"

        Rails.logger.info(
          "[Infrastructure] Scheduled connectivity monitoring " \
          "is disabled"
        )

        return
      end

      # --------------------------------------------------------
      # 2. Start a new monitoring run
      #
      # MonitoringRunStarter handles:
      # - Eligible asset selection
      # - Database concurrency protection
      # - Solid Queue job enqueueing
      # - Active Job UUID persistence
      # --------------------------------------------------------

      run = Infrastructure::MonitoringRunStarter.new.call

      # --------------------------------------------------------
      # 3. Record successful scheduling
      # --------------------------------------------------------

      Rails.logger.info(
        "[Infrastructure] Scheduled monitoring run #{run.id} " \
        "created, active_job_id=#{run.active_job_id}"
      )

    rescue Infrastructure::MonitoringRunStarter::AlreadyRunning
      # --------------------------------------------------------
      # Another monitoring run is already Queued or Running.
      # Skip this scheduled execution safely.
      # --------------------------------------------------------

      Rails.logger.info(
        "[Infrastructure] Scheduled check skipped: " \
        "another monitoring run is active"
      )

    rescue Infrastructure::MonitoringRunStarter::NoAssets
      # --------------------------------------------------------
      # No eligible infrastructure assets are available.
      # --------------------------------------------------------

      Rails.logger.info(
        "[Infrastructure] Scheduled check skipped: " \
        "no eligible infrastructure assets"
      )

    rescue Infrastructure::MonitoringRunStarter::EnqueueFailed => e
      # --------------------------------------------------------
      # The connectivity batch job could not be enqueued.
      # MonitoringRunStarter handles the run failure state.
      # --------------------------------------------------------

      Rails.logger.error(
        "[Infrastructure] Scheduled monitoring enqueue failed: " \
        "#{e.message}"
      )

      raise

    rescue Infrastructure::MonitoringRunStarter::JobIdentityPersistenceFailed => e
      # --------------------------------------------------------
      # The connectivity batch job was successfully enqueued,
      # but its Active Job UUID could not be persisted.
      #
      # Do not mark the monitoring run Failed here.
      # The worker may already be processing the batch.
      # --------------------------------------------------------

      Rails.logger.error(
        "[Infrastructure] Scheduled monitoring job identity " \
        "persistence failed: #{e.message}"
      )

      raise
    end
  end
end
