# frozen_string_literal: true

require "csv"

module Infrastructure
  # Read-only, bounded governance evidence snapshot.
  #
  # CSV values are neutralised against spreadsheet formula
  # injection through the shared NotificationCsvSanitizer.
  class NotificationGovernanceComplianceReport
    MAX_ROWS_PER_SECTION = 5_000

    SECTIONS = %w[
      summary
      policies
      policy_events
      legal_holds
      legal_hold_events
    ].freeze

    def initialize(assessed_at: Time.current)
      @assessed_at = assessed_at
    end

    def assessment
      @assessment ||= NotificationGovernanceSecurityAssessment.new.call
    end

    def section_counts
      {
        "policies" => NotificationRetentionPolicy.count,
        "policy_events" => NotificationRetentionEvent.count,
        "legal_holds" => NotificationLegalHold.count,
        "legal_hold_events" => NotificationLegalHoldEvent.count
      }
    end

    def csv(section:)
      unless SECTIONS.include?(section.to_s)
        raise ArgumentError, "Unsupported report section"
      end

      CSV.generate(headers: true) do |csv|
        case section.to_s
        when "summary"
          write_summary(csv)

        when "policies"
          write_policies(csv)

        when "policy_events"
          write_policy_events(csv)

        when "legal_holds"
          write_legal_holds(csv)

        when "legal_hold_events"
          write_legal_hold_events(csv)
        end
      end
    end

    private

    # ==========================================================
    # GOVERNANCE SUMMARY
    # ==========================================================

    def write_summary(csv)
      csv << %w[
        metric
        value
        assessed_at
      ]

      assessment.each do |metric, value|
        next if metric == :assessed_at

        csv << [
          safe(metric),
          safe(value),
          timestamp(@assessed_at)
        ]
      end
    end

    # ==========================================================
    # RETENTION POLICIES
    # ==========================================================

    def write_policies(csv)
      csv << %w[
        id
        reference
        name
        status
        retention_days
        version
        approved_by
        approved_at
        suspended_by
        suspended_at
        created_at
      ]

      NotificationRetentionPolicy
        .order(:id)
        .limit(MAX_ROWS_PER_SECTION)
        .each do |policy|

        csv << [
          policy.id,
          safe(policy.reference),
          safe(policy.name),
          safe(policy.status),
          policy.retention_days,
          policy.version,
          safe(policy.approved_by),
          timestamp(policy.approved_at),
          safe(policy.suspended_by),
          timestamp(policy.suspended_at),
          timestamp(policy.created_at)
        ]
      end
    end

    # ==========================================================
    # RETENTION POLICY AUDIT EVENTS
    # ==========================================================

    def write_policy_events(csv)
      csv << %w[
        id
        policy_id
        action
        actor
        from_status
        to_status
        policy_version
        created_at
      ]

      NotificationRetentionEvent
        .order(:id)
        .limit(MAX_ROWS_PER_SECTION)
        .each do |event|

        csv << [
          event.id,
          event.notification_retention_policy_id,
          safe(event.action),
          safe(event.actor),
          safe(event.from_status),
          safe(event.to_status),
          event.policy_version,
          timestamp(event.created_at)
        ]
      end
    end

    # ==========================================================
    # LEGAL HOLDS
    # ==========================================================

    def write_legal_holds(csv)
      csv << %w[
        id
        notification_id
        reference
        reason
        placed_by
        placed_at
        released_by
        released_at
      ]

      NotificationLegalHold
        .order(:id)
        .limit(MAX_ROWS_PER_SECTION)
        .each do |hold|

        csv << [
          hold.id,
          hold.infrastructure_notification_id,
          safe(hold.reference),
          safe(hold.reason),
          safe(hold.placed_by),
          timestamp(hold.placed_at),
          safe(hold.released_by),
          timestamp(hold.released_at)
        ]
      end
    end

    # ==========================================================
    # LEGAL HOLD AUDIT EVENTS
    # ==========================================================

    def write_legal_hold_events(csv)
      csv << %w[
        id
        legal_hold_id
        action
        actor
        justification
        created_at
      ]

      NotificationLegalHoldEvent
        .order(:id)
        .limit(MAX_ROWS_PER_SECTION)
        .each do |event|

        csv << [
          event.id,
          event.notification_legal_hold_id,
          safe(event.action),
          safe(event.actor),
          safe(event.justification),
          timestamp(event.created_at)
        ]
      end
    end

    # ==========================================================
    # SHARED SECURITY HELPERS
    # ==========================================================

    def timestamp(value)
      value&.utc&.iso8601
    end

    def safe(value)
      NotificationCsvSanitizer.sanitize(value.to_s)
    end
  end
end