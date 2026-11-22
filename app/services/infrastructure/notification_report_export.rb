# frozen_string_literal: true

require "csv"

module Infrastructure
  class NotificationReportExport
    PERIODS = Infrastructure::NotificationAnalytics::PERIODS.freeze
    TYPES = %w[history attempts analytics].freeze
    MAX_ROWS = 10_000

    attr_reader :period, :type, :status, :event_type, :since, :until_at

    def initialize(period: "7d", type: "history", status: nil, event_type: nil, now: Time.current)
      @period = PERIODS.key?(period.to_s) ? period.to_s : "7d"
      @type = TYPES.include?(type.to_s) ? type.to_s : "history"
      @status = InfrastructureNotification::STATUSES.include?(status.to_s) ? status.to_s : ""
      @event_type = InfrastructureNotification::EVENTS.include?(event_type.to_s) ? event_type.to_s : ""
      @until_at = now
      @since = now - PERIODS.fetch(@period)
    end

    def filename
      "herga-notifications-#{type}-#{period}-#{until_at.utc.strftime('%Y%m%d-%H%M%S')}.csv"
    end

    def csv
      CSV.generate(headers: true) do |output|
        case type
        when "history" then write_history(output)
        when "attempts" then write_attempts(output)
        when "analytics" then write_analytics(output)
        end
      end
    end

    def history_count
      history_scope.count
    end

    def attempts_count
      attempts_scope.count
    end

    private

    def history_scope
      scope = InfrastructureNotification.where(created_at: since..until_at)
      scope = scope.where(status: status) if status.present?
      scope = scope.where(event_type: event_type) if event_type.present?
      scope
    end

    def attempts_scope
      scope = InfrastructureNotificationAttempt
        .joins(:infrastructure_notification)
        .where(attempted_at: since..until_at)
      scope = scope.where(status: status) if status.present?
      scope = scope.where(infrastructure_notifications: { event_type: event_type }) if event_type.present?
      scope
    end

    def write_history(output)
      output << %w[notification_id event_type status source_type source_id escalation_level attempt_count occurred_at_utc created_at_utc attempted_at_utc accepted_at_utc]
      history_scope.order(created_at: :desc, id: :desc).limit(MAX_ROWS).each do |record|
        output << safe_row([
          record.id, record.event_type, record.status, record.source_type,
          record.source_id, record.escalation_level, record.attempt_count,
          timestamp(record.occurred_at), timestamp(record.created_at),
          timestamp(record.attempted_at), timestamp(record.accepted_at)
        ])
      end
    end

    def write_attempts(output)
      output << %w[attempt_id notification_id event_type status attempted_at_utc]
      attempts_scope.order(attempted_at: :desc, id: :desc).limit(MAX_ROWS).each do |record|
        output << safe_row([
          record.id, record.infrastructure_notification_id,
          record.infrastructure_notification.event_type,
          record.status, timestamp(record.attempted_at)
        ])
      end
    end

    def write_analytics(output)
      # Use the same selected notification population as the history export.
      # This avoids mixing created-at and attempted-at reporting populations.
      counts = history_scope.group(:status).count
      total = counts.values.sum
      output << %w[metric category count percentage]
      output << ["Notifications created", "All", total, ""]
      InfrastructureNotification::STATUSES.each do |value|
        count = counts.fetch(value, 0)
        output << ["Current status", value, count, total.zero? ? 0.0 : (count * 100.0 / total).round(1)]
      end
      event_counts = history_scope.group(:event_type).count
      InfrastructureNotification::EVENTS.each do |value|
        output << ["Event type", value, event_counts.fetch(value, 0), ""]
      end
      output << ["Reporting period", period, "", ""]
      output << ["Period start UTC", timestamp(since), "", ""]
      output << ["Period end UTC", timestamp(until_at), "", ""]
    end

    def timestamp(value)
      value&.utc&.iso8601
    end

    def safe_row(values)
      values.map do |value|
        next value unless value.is_a?(String)
        # Prefix any string beginning with a spreadsheet formula trigger,
        # including triggers after whitespace/control characters.
        value.match?(/\A[\s\x00-\x1f]*[=+@-]/) ? "'#{value}" : value
      end
    end
  end
end
