# frozen_string_literal: true

module Infrastructure
  class NotificationsController < ApplicationController
    before_action :require_portal_administrator

    def index
      @page = [params[:page].to_i, 1].max
      @page = 1 if @page > 100_000
      @enabled = NotificationSettings.enabled?
      @summary = InfrastructureNotification.group(:status).count
      scope = InfrastructureNotification.recent
      @total = scope.count
      @total_pages = [(@total.to_f / 25).ceil, 1].max
      @page = [@page, @total_pages].min
      @notifications = scope.offset((@page - 1) * 25).limit(25)
    end
  end
end
