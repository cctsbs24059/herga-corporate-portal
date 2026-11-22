# frozen_string_literal: true

module Infrastructure
  class ScheduledAvailabilityAssessmentJob < ApplicationJob
    queue_as :default

    def perform
      unless ENV.fetch("HERGA_AVAILABILITY_ASSESSMENTS_ENABLED", "false") == "true"
        Rails.logger.info("[Infrastructure] Scheduled availability assessments disabled")
        return
      end

      result = Infrastructure::AvailabilityAssessor.new(
        threshold: ENV.fetch("HERGA_AVAILABILITY_THRESHOLD_PERCENT", "99"),
        period_hours: ENV.fetch("HERGA_AVAILABILITY_PERIOD_HOURS", "24")
      ).call
      alerts = Infrastructure::AvailabilityAlertReconciler.new.call(period_end: result.fetch(:period_end))
      Rails.logger.info("[Infrastructure] Availability assessment completed: #{result.inspect}; alerts: #{alerts.inspect}")
      result
    end
  end
end
