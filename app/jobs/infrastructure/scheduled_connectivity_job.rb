
# frozen_string_literal: true

module Infrastructure
  class ScheduledConnectivityJob < ApplicationJob
    queue_as :default

    def perform
      unless ENV.fetch("HERGA_CONNECTIVITY_MONITORING_ENABLED", "false") == "true"
        Rails.logger.info(
          "[Infrastructure] Scheduled connectivity monitoring is disabled"
        )
        return
      end

      run = Infrastructure::MonitoringRunStarter.new.call

      Rails.logger.info(
        "[Infrastructure] Scheduled monitoring run #{run.id} created"
      )

    rescue Infrastructure::MonitoringRunStarter::AlreadyRunning
      Rails.logger.info(
        "[Infrastructure] Scheduled check skipped: " \
        "another monitoring run is active"
      )

    rescue Infrastructure::MonitoringRunStarter::NoAssets
      Rails.logger.info(
        "[Infrastructure] Scheduled check skipped: " \
        "no eligible infrastructure assets"
      )

    rescue Infrastructure::MonitoringRunStarter::EnqueueFailed => e
      Rails.logger.error(
        "[Infrastructure] Scheduled monitoring enqueue failed: #{e.message}"
      )
      raise
    end
  end
end
