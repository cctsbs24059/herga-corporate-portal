# frozen_string_literal: true

module Infrastructure
  # Read-only policy metadata. This is NOT an approval or disposal engine.
  class NotificationRetentionGovernance
    STATES = %w[Draft Approved Suspended].freeze
    DEFAULT_DAYS = 365
    MIN_DAYS = 30
    MAX_DAYS = 3650

    def initialize(settings: ENV)
      @settings = settings
    end

    def call
      days = valid_days(@settings["HERGA_NOTIFICATION_RETENTION_DAYS"])
      requested_state = @settings["HERGA_NOTIFICATION_RETENTION_POLICY_STATUS"].to_s
      reference = @settings["HERGA_NOTIFICATION_RETENTION_POLICY_REFERENCE"].to_s.strip
      approved_by = @settings["HERGA_NOTIFICATION_RETENTION_APPROVED_BY"].to_s.strip
      approved_on = valid_date(@settings["HERGA_NOTIFICATION_RETENTION_APPROVED_ON"])
      valid_state = STATES.include?(requested_state)
      complete_approval = requested_state == "Approved" &&
                          reference.present? && approved_by.present? && approved_on.present?

      # Missing or inconsistent metadata is not an effective approval.
      state = complete_approval ? "Approved" : (requested_state == "Suspended" ? "Suspended" : "Draft")

      {
        policy_status: state,
        requested_status: valid_state ? requested_state : "Draft",
        metadata_complete: complete_approval,
        policy_reference: reference.presence,
        approved_by: approved_by.presence,
        approved_on: approved_on,
        retention_days: days,
        protected_statuses: %w[Pending Sending Unknown].freeze,
        disposal_authorized: false,
        read_only: true,
        warnings: warnings(requested_state, days, reference, approved_by, approved_on)
      }
    end

    private

    def valid_days(value)
      days = Integer(value || DEFAULT_DAYS)
      days.between?(MIN_DAYS, MAX_DAYS) ? days : DEFAULT_DAYS
    rescue ArgumentError, TypeError
      DEFAULT_DAYS
    end

    def valid_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end

    def warnings(state, days, reference, approved_by, approved_on)
      result = []
      result << "Invalid policy status; treated as Draft." unless STATES.include?(state)
      if state == "Approved" && (reference.blank? || approved_by.blank? || approved_on.nil?)
        result << "Approval metadata is incomplete or invalid; effective status is Draft."
      end
      result << "Retention period is provisional; it does not permit disposal." if days
      result
    end
  end
end
