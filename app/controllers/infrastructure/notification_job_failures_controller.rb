# frozen_string_literal: true

module Infrastructure
  class NotificationJobFailuresController < ApplicationController
    before_action :require_portal_administrator

    def index
      @job_class = params[:job_class].to_s
      @period = params[:period].to_s
      result = NotificationFailureInvestigation.new.list(
        job_class: @job_class, period: @period, page: params[:page] || 1
      )
      @failures = result.fetch(:failures)
      @total = result.fetch(:total)
      @page = result.fetch(:page)
      @total_pages = result.fetch(:total_pages)
    end

    def show
      @failure = NotificationFailureInvestigation.new.find(params[:id])
      @notification = if @failure[:notification_id]
                        InfrastructureNotification.find_by(id: @failure[:notification_id])
                      end
    end
  end
end
