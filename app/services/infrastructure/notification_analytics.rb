# frozen_string_literal: true

module Infrastructure
  class NotificationAnalytics
    PERIODS = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }.freeze

    def initialize(period: "7d", now: Time.current)
      @period = PERIODS.key?(period) ? period : "7d"
      @now = now
    end

    def call
      since = @now - PERIODS.fetch(@period)
      notifications = InfrastructureNotification.where(created_at: since..@now)
      attempts = InfrastructureNotificationAttempt.where(attempted_at: since..@now)
      status_counts = notifications.group(:status).count
      total = status_counts.values.sum
      accepted = status_counts.fetch("Accepted", 0)
      unknown = status_counts.fetch("Unknown", 0)
      durations = notifications.where(status: "Accepted")
        .where.not(attempted_at: nil, accepted_at: nil)
        .where("accepted_at >= attempted_at")
        .pluck(:attempted_at, :accepted_at)
        .map { |started, finished| finished - started }

      {
        period: @period, since: since, until_at: @now,
        total: total, statuses: InfrastructureNotification::STATUSES.index_with { |s| status_counts.fetch(s, 0) },
        accepted_percentage: total.zero? ? 0.0 : (accepted * 100.0 / total).round(1),
        unknown_percentage: total.zero? ? 0.0 : (unknown * 100.0 / total).round(1),
        events: InfrastructureNotification::EVENTS.index_with { |event| notifications.where(event_type: event).count },
        attempts: { total: attempts.count, accepted: attempts.where(status: "Accepted").count,
                    unknown: attempts.where(status: "Unknown").count },
        average_processing_seconds: durations.empty? ? nil : (durations.sum / durations.length).round(2),
        daily: daily_counts(notifications)
      }
    end

    private

    def daily_counts(notifications)
      # Aggregate using PostgreSQL date boundaries in UTC, matching the displayed UTC labels.
      rows = notifications.group(Arel.sql("DATE(created_at AT TIME ZONE 'UTC')"), :status).count
      rows.each_with_object({}) do |((date, status), count), result|
        key = date.to_s
        result[key] ||= InfrastructureNotification::STATUSES.index_with { 0 }
        result[key][status] = count if result[key].key?(status)
      end.sort.to_h
    end
  end
end
