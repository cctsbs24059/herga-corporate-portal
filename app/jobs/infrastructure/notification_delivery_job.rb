
# frozen_string_literal: true

module Infrastructure
  class NotificationDeliveryJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      return unless NotificationSettings.enabled?

      notification = InfrastructureNotification.find_by(id: notification_id)
      return unless notification

      cutoff = NotificationSettings.activation_time

      # Never deliver notifications outside the activation window.
      return if cutoff.nil?
      return if notification.occurred_at.nil?
      return if notification.occurred_at < cutoff
      return if notification.occurred_at > Time.current

      # Prevent duplicate sends from concurrent workers.
      claimed = InfrastructureNotification
        .where(id: notification.id, status: "Pending")
        .update_all(
          status: "Sending",
          attempted_at: Time.current,
          updated_at: Time.current
        )

      return unless claimed == 1

      begin
        # Render the existing Rails mailer without using SMTP.
        message = InfrastructureNotificationMailer
          .event(notification.id)
          .message

        body = if message.multipart?
                 message.text_part&.body&.decoded
               else
                 message.body.decoded
               end

        raise "Notification email body is empty" if body.blank?

        # Send through Microsoft Graph.
        Infrastructure::MicrosoftGraphMailSender.new.deliver!(
          to: notification.recipient,
          subject: message.subject,
          body: body
        )

        now = Time.current

        notification.update!(
          status: "Accepted",
          accepted_at: now,
          last_error: nil
        )

        notification.infrastructure_notification_attempts.create!(
          status: "Accepted",
          attempted_at: now
        )

        Rails.logger.info(
          "[InfrastructureNotifications] " \
          "id=#{notification.id} Graph submission accepted"
        )

      rescue StandardError => e
        # Do not retry automatically: Graph may have accepted
        # the message before a network error was reported.
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
