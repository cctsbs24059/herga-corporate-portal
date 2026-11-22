
# frozen_string_literal: true

module Infrastructure
  class NotificationReconciliationJob < ApplicationJob
    queue_as :default

    def perform
      return unless NotificationSettings.enabled?

      cutoff = NotificationSettings.activation_time

      result = NotificationReconciler.new.call

      Rails.logger.info(
        "[InfrastructureNotifications] reconciliation=#{result.inspect}"
      )

      InfrastructureNotification
        .where(status: "Pending")
        .where(occurred_at: cutoff..Time.current)
        .order(:id)
        .limit(100)
        .pluck(:id)
        .each do |id|

        NotificationDeliveryJob.perform_later(id)
      end
    end
  end
end
