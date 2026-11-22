
# frozen_string_literal: true

module Infrastructure
  class NotificationsController < ApplicationController
    before_action :require_portal_administrator
    before_action :set_notification, only: :show

    PER_PAGE = 25

    def index
      @enabled = NotificationSettings.enabled?
      @activation_time = NotificationSettings.activation_time

      @summary = InfrastructureNotification.group(:status).count
      @total_notifications = @summary.values.sum

      @statuses = InfrastructureNotification::STATUSES
      @events = InfrastructureNotification::EVENTS

      @status_filter = params[:status].to_s
      @event_filter = params[:event_type].to_s
      @search = params[:q].to_s.strip.first(100)

      scope = InfrastructureNotification.recent

      if @statuses.include?(@status_filter)
        scope = scope.where(status: @status_filter)
      end

      if @events.include?(@event_filter)
        scope = scope.where(event_type: @event_filter)
      end

      if @search.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"

        scope = scope.where(
          "recipient ILIKE :q OR event_key ILIKE :q OR " \
          "CAST(id AS TEXT) ILIKE :q",
          q: pattern
        )
      end

      @total = scope.count

      @page = params[:page].to_i
      @page = 1 if @page < 1
      @page = [@page, 100_000].min

      @total_pages = [(@total.to_f / PER_PAGE).ceil, 1].max
      @page = [@page, @total_pages].min

      @notifications = scope
        .offset((@page - 1) * PER_PAGE)
        .limit(PER_PAGE)
        .to_a
    end

    def show
      @attempts = @notification
        .infrastructure_notification_attempts
        .order(attempted_at: :desc, id: :desc)

      @source = case @notification.source_type
                when "InfrastructureIncident"
                  InfrastructureIncident.find_by(
                    id: @notification.source_id
                  )
                when "InfrastructureAvailabilityAlert"
                  InfrastructureAvailabilityAlert.find_by(
                    id: @notification.source_id
                  )
                when "InfrastructureAsset"
                  InfrastructureAsset.find_by(
                    id: @notification.source_id
                  )
                end

      @asset = if @source.is_a?(InfrastructureAsset)
                 @source
               else
                 @source&.infrastructure_asset
               end
    end

    private

    def set_notification
      @notification = InfrastructureNotification.find(params[:id])
    end
  end
end
