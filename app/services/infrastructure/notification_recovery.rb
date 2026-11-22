
# frozen_string_literal: true

module Infrastructure
  class NotificationRecovery
    STALE_AFTER = 30.minutes

    def call(now: Time.current)
      recovered = 0
      cutoff = now - STALE_AFTER

      InfrastructureNotification
        .where(status: "Sending")
        .where("attempted_at <= ?", cutoff)
        .find_each do |notification|

        notification.with_lock do
          next unless notification.status == "Sending"
          next unless notification.attempted_at
          next if notification.attempted_at > cutoff

          message =
            "Delivery worker did not complete within " \
            "#{STALE_AFTER.inspect}. " \
            "Microsoft Graph submission outcome is unknown. " \
            "Manual investigation required."

          notification.update!(
            status: "Unknown",
            last_error: message,
            attempt_count: notification.attempt_count.to_i + 1
          )

          notification.infrastructure_notification_attempts.create!(
            status: "Unknown",
            attempted_at: now,
            error_class: "StaleDeliveryRecovery",
            error_message: message
          )

          recovered += 1

          Rails.logger.warn(
            "[InfrastructureNotifications] " \
            "id=#{notification.id} recovered from stale Sending state"
          )
        end
      end

      { recovered: recovered }
    end
  end
end
