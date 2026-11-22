
# frozen_string_literal: true

class InfrastructureNotificationMailer < ApplicationMailer
  def event(notification_id)
    @notification = InfrastructureNotification.find(notification_id)

    @source = case @notification.source_type
              when "InfrastructureIncident"
                InfrastructureIncident.find_by(id: @notification.source_id)
              when "InfrastructureAvailabilityAlert"
                InfrastructureAvailabilityAlert.find_by(id: @notification.source_id)
              when "InfrastructureAsset"
                InfrastructureAsset.find_by(id: @notification.source_id)
              end

    @asset = if @source.is_a?(InfrastructureAsset)
               @source
             else
               @source&.infrastructure_asset
             end

    @test_notification =
      @notification.event_key.start_with?("HERGA-GRAPH-TEST-")

    subject = if @test_notification
                "[HERGA TEST - NO ACTION REQUIRED] Microsoft Graph Notification"
              else
                "[HERGA Infrastructure] " \
                  "#{@notification.event_type.underscore.humanize} — " \
                  "#{@asset&.hostname || 'Asset unavailable'}"
              end

    mail(
      to: @notification.recipient,
      from: ENV.fetch(
        "HERGA_NOTIFICATION_FROM",
        "info@hergafarmsgroup.com"
      ),
      subject: subject
    )
  end
end
