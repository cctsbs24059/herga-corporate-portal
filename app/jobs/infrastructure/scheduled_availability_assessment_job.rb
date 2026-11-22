
# frozen_string_literal: true

module Infrastructure
  class ScheduledAvailabilityAssessmentJob < ApplicationJob
    queue_as :default

    def perform
      unless assessments_enabled?
        Rails.logger.info(
          "[Infrastructure] Scheduled availability assessments disabled"
        )
        return
      end

      Rails.logger.info(
        "[Infrastructure] Starting scheduled availability assessment"
      )

      assessment_result = Infrastructure::AvailabilityAssessor.new(
        threshold: ENV.fetch(
          "HERGA_AVAILABILITY_THRESHOLD_PERCENT",
          "99"
        ),
        period_hours: ENV.fetch(
          "HERGA_AVAILABILITY_PERIOD_HOURS",
          "24"
        )
      ).call

      Rails.logger.info(
        "[Infrastructure] Availability assessment completed: " \
        "#{assessment_result.inspect}"
      )

      period_end = assessment_result.fetch(:period_end)

      if period_end.blank?
        raise ArgumentError,
              "Availability assessment did not return period_end"
      end

      Rails.logger.info(
        "[Infrastructure] Starting availability alert reconciliation"
      )

      reconciliation_result =
        Infrastructure::AvailabilityAlertReconciler.new.call(
          period_end: period_end
        )

      Rails.logger.info(
        "[Infrastructure] Availability alert reconciliation completed: " \
        "#{reconciliation_result.inspect}"
      )

      {
        assessment: assessment_result,
        reconciliation: reconciliation_result
      }
    rescue StandardError => e
      Rails.logger.error(
        "[Infrastructure] Scheduled availability assessment failed: " \
        "#{e.class}: #{e.message}"
      )

      raise
    end

    private

    def assessments_enabled?
      ENV.fetch(
        "HERGA_AVAILABILITY_ASSESSMENTS_ENABLED",
        "false"
      ) == "true"
    end
  end
end
