
# frozen_string_literal: true

module Infrastructure
  class StaleMonitoringRunRecoveryJob < ApplicationJob
    queue_as :default

    def perform
      unless ENV.fetch(
        "HERGA_MONITORING_RECOVERY_ENABLED",
        "false"
      ) == "true"
        Rails.logger.info(
          "[Infrastructure] Automatic stale monitoring recovery is disabled"
        )

        return
      end

      Rails.logger.info(
        "[Infrastructure] Starting stale monitoring run recovery"
      )

      Infrastructure::StaleMonitoringRunRecovery.new.call

      Rails.logger.info(
        "[Infrastructure] Stale monitoring run recovery completed"
      )
    end
  end
end
