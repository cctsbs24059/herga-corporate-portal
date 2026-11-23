# frozen_string_literal: true

module Infrastructure
  # Read-only consistency checks. This is not cryptographic tamper detection.
  class NotificationLegalHoldAuditVerifier
    def call
      holds = NotificationLegalHold
      events = NotificationLegalHoldEvent
      {
        active_holds: holds.active.count,
        released_holds: holds.where.not(released_at: nil).count,
        release_events: events.where(action: "Released").count,
        released_without_event: holds.where.not(released_at: nil)
          .where.not(id: events.where(action: "Released").select(:notification_legal_hold_id)).count,
        active_with_release_event: holds.active
          .where(id: events.where(action: "Released").select(:notification_legal_hold_id)).count,
        multiple_release_events: events.where(action: "Released")
          .group(:notification_legal_hold_id).having("COUNT(*) > 1").count.length,
        append_only_trigger_enabled: trigger_enabled?
      }
    end

    private

    def trigger_enabled?
      sql = <<~SQL
        SELECT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgrelid = 'infrastructure_notification_legal_hold_events'::regclass
            AND tgname = 'herga_legal_hold_events_append_only'
            AND tgenabled IN ('O', 'A')
        )
      SQL
      ActiveRecord::Base.connection.select_value(sql)
    end
  end
end
