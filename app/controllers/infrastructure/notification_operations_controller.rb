# frozen_string_literal: true

module Infrastructure
  class NotificationOperationsController < ApplicationController
    before_action -> { require_portal_permission(:governance_read) }

    def index
      requested_period = params[:period].to_s
      @period = Infrastructure::NotificationAnalytics::PERIODS.key?(requested_period) ? requested_period : "7d"

      @analytics = Infrastructure::NotificationAnalytics.new(period: @period).call
      @queue_health = Infrastructure::NotificationQueueHealth.new.call
      @job_diagnostics = Infrastructure::NotificationJobDiagnostics.new.call
      @notification_enabled = Infrastructure::NotificationSettings.enabled?
      @notification_activation_time = Infrastructure::NotificationSettings.activation_time
      @health_assessment = Infrastructure::NotificationHealthAssessment.new(
        queue_health: @queue_health,
        job_diagnostics: @job_diagnostics,
        enabled: @notification_enabled
      ).call
    end
  end
end
