
# frozen_string_literal: true

module Infrastructure
  class NotificationSettings
    RECIPIENT = "info@hergafarmsgroup.com"

    def self.enabled?
      ENV["HERGA_NOTIFICATIONS_ENABLED"] == "true" &&
        activation_time.present? &&
        Time.current >= activation_time
    end

    def self.activation_time
      raw = ENV["HERGA_NOTIFICATIONS_START_AT"].to_s
      return nil if raw.blank?

      Time.iso8601(raw)
    rescue ArgumentError
      nil
    end

    def self.escalation_minutes
      value = Integer(
        ENV.fetch("HERGA_NOTIFICATION_ESCALATION_MINUTES", "60"),
        10
      )

      value.clamp(1, 1440)
    rescue ArgumentError
      60
    end
  end
end
