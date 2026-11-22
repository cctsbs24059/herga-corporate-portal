# frozen_string_literal: true

module Infrastructure
  class ExecutiveOverview
    attr_reader :analytics, :assets, :incidents, :alerts, :latest_assessment,
                :latest_run, :queue_health

    def initialize(params: {})
      @params = params
    end

    def call
      @analytics = Infrastructure::MonitoringAnalytics.new(params: @params).call
      @assets = InfrastructureAsset.group(:status).count
      @incidents = InfrastructureIncident.group(:status).count
      @alerts = InfrastructureAvailabilityAlert.group(:status).count
      @latest_assessment = InfrastructureAvailabilityAssessment.maximum(:period_end)
      @latest_run = InfrastructureMonitoringRun.order(created_at: :desc).first
      @queue_health = Infrastructure::SolidQueueHealth.new.call
      self
    end

    def asset_total = assets.values.sum
    def incident_total = incidents.values.sum
    def alert_total = alerts.values.sum
  end
end
