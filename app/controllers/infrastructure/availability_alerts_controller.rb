
# frozen_string_literal: true

module Infrastructure
  class AvailabilityAlertsController < ApplicationController
    before_action -> { require_portal_permission(:infrastructure_read) },
                  only: %i[index show]

    before_action -> { require_portal_permission(:infrastructure_manage) },
                  only: :acknowledge

    before_action :set_alert, only: %i[show acknowledge]

    def index
      @status = params[:status].to_s
      @status = "Unresolved" unless %w[Unresolved Active Acknowledged Cleared All].include?(@status)

      relation = InfrastructureAvailabilityAlert.includes(
        :infrastructure_asset, :acknowledged_by
      )

      relation = case @status
                 when "Unresolved" then relation.unresolved
                 when "All" then relation
                 else relation.where(status: @status)
                 end

      @alerts = relation.recent.limit(200)
      @active_count = InfrastructureAvailabilityAlert.where(status: "Active").count
      @acknowledged_count = InfrastructureAvailabilityAlert.where(status: "Acknowledged").count
      @cleared_count = InfrastructureAvailabilityAlert.where(status: "Cleared").count
    end

    def show; end

    def acknowledge
      if @alert.status == "Active"
        @alert.update!(
          status: "Acknowledged",
          acknowledged_by: current_user,
          acknowledged_at: Time.current
        )

        redirect_to infrastructure_availability_alert_path(@alert),
                    notice: "Availability alert acknowledged."
      else
        redirect_to infrastructure_availability_alert_path(@alert),
                    alert: "Only active alerts can be acknowledged."
      end
    end

    private

    def set_alert
      @alert = InfrastructureAvailabilityAlert
        .includes(:infrastructure_asset, :acknowledged_by)
        .find(params[:id])
    end
  end
end
