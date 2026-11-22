# frozen_string_literal: true

module Infrastructure
  class NotificationAnalyticsController < ApplicationController
    before_action :require_portal_administrator

    def index
      @period = Infrastructure::NotificationAnalytics::PERIODS.key?(params[:period].to_s) ? params[:period].to_s : "7d"
      @analytics = Infrastructure::NotificationAnalytics.new(period: @period).call
    end
  end
end
