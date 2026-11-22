
# frozen_string_literal: true

module Infrastructure
  class NotificationDeliveryJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      return unless NotificationSettings.enabled?

      notification = InfrastructureNotification.find_by(id: notification_id)
      return unless notification

      # Do not send notifications for events before activation.
      activation_time = NotificationSettings.activation_time
      return unless activation_time
      return if notification.occurred_at.blank?
      return if notification.occurred_at < activation_time

      # Atomically claim a pending notification.
      claimed = InfrastructureNotification
        .where(id: notification.id, status: "Pending")
        .update_all(
          status: "Sending",
          attempted_at: Time.current,
          updated_at: Time.current
        )

      return unless claimed == 1

      begin
        # Build the message using the existing Rails mailer.
        message = InfrastructureNotificationMailer
          .event(notification.id)
          .message

        # Extract a plain-text body for Microsoft Graph.
        body = if message.multipart?
                 message.text_part&.body&.decoded
               else
                 message.body.decoded
               end

        raise "Notification email has no plain-text body" if body.blank?

        # Deliver using the verified Microsoft Graph integration.
        Infrastructure::MicrosoftGraphMailSender.new.deliver!(
          to: notification.recipient,
          subject: message.subject,
          body: body
        )

        notification.update!(
          status: "Accepted",
          accepted_at: Time.current,
          last_error: nil
        )

        notification.infrastructure_notification_attempts.create!(
          status: "Accepted",
          attempted_at: Time.current
        )

        Rails.logger.info(
          "[InfrastructureNotifications] " \
          "id=#{notification.id} accepted by Microsoft Graph"
        )

      rescue StandardError => e
        # Avoid automatic retries: Graph may have accepted
        # the message before a network failure was reported.
        error = "#{e.class}: #{e.message}".truncate(1000)

        Rails.logger.error(
          "[InfrastructureNotifications] id=#{notification.id} #{error}"
        )

        notification.update!(
          status: "Unknown",
          last_error: error
        )

        notification.infrastructure_notification_attempts.create!(
          status: "Unknown",
          attempted_at: Time.current,
          error_message: error
        )
      end
    end
  end
end
