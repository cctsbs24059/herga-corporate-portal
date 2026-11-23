# frozen_string_literal: true

require "csv"

module Infrastructure
  # Read-only, bounded governance evidence snapshot.
  # CSV values are neutralised against spreadsheet formula injection.
  class NotificationGovernanceComplianceReport
    MAX_ROWS_PER_SECTION = 5_000
    SECTIONS = %w[summary policies policy_events legal_holds legal_hold_events].freeze

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
      raise ArgumentError, "Unsupported report section" unless SECTIONS.include?(section.to_s)

      CSV.generate(headers: true) do |csv|
        case section.to_s
        when "summary"
          csv << %w[metric value assessed_at]
          assessment.each do |metric, value|
            next if metric == :assessed_at
            csv << [safe(metric), safe(value), timestamp(@assessed_at)]
          end
        when "policies"
          csv << %w[id reference name status retention_days version approved_by approved_at suspended_by suspended_at created_at]
          NotificationRetentionPolicy.order(:id).limit(MAX_ROWS_PER_SECTION).each do |p|
            csv << [p.id, safe(p.reference), safe(p.name), safe(p.status), p.retention_days,
                    p.version, safe(p.approved_by), timestamp(p.approved_at),
                    safe(p.suspended_by), timestamp(p.suspended_at), timestamp(p.created_at)]
          end
        when "policy_events"
          csv << %w[id policy_id action actor from_status to_status policy_version created_at]
          NotificationRetentionEvent.order(:id).limit(MAX_ROWS_PER_SECTION).each do |e|
            csv << [e.id, e.notification_retention_policy_id, safe(e.action), safe(e.actor),
                    safe(e.from_status), safe(e.to_status), e.policy_version, timestamp(e.created_at)]
          end
        when "legal_holds"
          csv << %w[id notification_id reference reason placed_by placed_at released_by released_at]
          NotificationLegalHold.order(:id).limit(MAX_ROWS_PER_SECTION).each do |h|
            csv << [h.id, h.infrastructure_notification_id, safe(h.reference), safe(h.reason),
                    safe(h.placed_by), timestamp(h.placed_at), safe(h.released_by), timestamp(h.released_at)]
          end
        when "legal_hold_events"
          csv << %w[id legal_hold_id action actor justification created_at]
          NotificationLegalHoldEvent.order(:id).limit(MAX_ROWS_PER_SECTION).each do |e|
            csv << [e.id, e.notification_legal_hold_id, safe(e.action), safe(e.actor),
                    safe(e.justification), timestamp(e.created_at)]
          end
        end
      end
    end

    private

    def timestamp(value)
      value&.utc&.iso8601
    end

    def safe(value)
      str = value.to_s
      # Neutralise leading spreadsheet formula characters, including whitespace-prefixed formulas.
      str.match?(/\A\s*[=+@-]/) ? "'#{str}" : str
    end
  end
end
