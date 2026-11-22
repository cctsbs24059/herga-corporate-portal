
# frozen_string_literal: true

module Infrastructure
  class NotificationDeliveryJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      return unless NotificationSettings.enabled?

      notification = InfrastructureNotification.find_by(id: notification_id)
      return unless notification

      cutoff = NotificationSettings.activation_time
      now = Time.current

      return if cutoff.nil?
      return if notification.occurred_at.nil?
      return if notification.occurred_at < cutoff
      return if notification.occurred_at > now

      # Atomically claim a Pending notification.
      claimed = InfrastructureNotification
        .where(id: notification.id, status: "Pending")
        .update_all(
          status: "Sending",
          attempted_at: now,
          last_attempt_at: now,
          updated_at: now
        )

      return unless claimed == 1

      begin
        message = InfrastructureNotificationMailer
          .event(notification.id)
          .message

        body = if message.multipart?
                 message.text_part&.body&.decoded
               else
                 message.body.decoded
               end

        raise "Notification email body is empty" if body.blank?

        # Microsoft Graph submission.
        Infrastructure::MicrosoftGraphMailSender.new.deliver!(
          to: notification.recipient,
          subject: message.subject,
          body: body
        )

        # Record acceptance and audit atomically.
        notification.with_lock do
          if notification.status == "Sending"
            accepted_at = Time.current

            notification.update!(
              status: "Accepted",
              accepted_at: accepted_at,
              last_error: nil,
              attempt_count: notification.attempt_count.to_i + 1
            )

            notification.infrastructure_notification_attempts.create!(
              status: "Accepted",
              attempted_at: accepted_at
            )
          else
            Rails.logger.warn(
              "[InfrastructureNotifications] " \
              "id=#{notification.id} Graph accepted, but status " \
              "changed to #{notification.status} before recording"
            )
          end
        end

        Rails.logger.info(
          "[InfrastructureNotifications] " \
          "id=#{notification.id} Graph submission completed"
        )

      rescue StandardError => e
        error = "#{e.class}: #{e.message}".truncate(1000)

        Rails.logger.error(
          "[InfrastructureNotifications] id=#{notification.id} #{error}"
        )

        # Do not retry automatically.
        # A timeout may occur after Graph accepted the message.
        begin
          notification.with_lock do
            if notification.status == "Sending"
              notification.update!(
                status: "Unknown",
                last_error: error,
                attempt_count: notification.attempt_count.to_i + 1
              )

              notification.infrastructure_notification_attempts.create!(
                status: "Unknown",
                attempted_at: Time.current,
                error_message: error,
                error_class: e.class.name
              )
            end
          end
        rescue StandardError => audit_error
          Rails.logger.error(
            "[InfrastructureNotifications] " \
            "id=#{notification.id} audit persistence failed: " \
            "#{audit_error.class}: #{audit_error.message}"
          )

          # Surface database failures to the job infrastructure.
          # The notification is no longer Pending, so replaying
          # this job cannot automatically resend it.
          raise
        end
      end
    end
  end
end
