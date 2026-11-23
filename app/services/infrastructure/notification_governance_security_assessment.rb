# frozen_string_literal: true

module Infrastructure
  # Read-only checks of governance record consistency and database protections.
  # Results are indicators, not a cryptographic attestation or access-control penetration test.
  class NotificationGovernanceSecurityAssessment
    def call
      policies = NotificationRetentionPolicy
      policy_events = NotificationRetentionEvent
      holds = NotificationLegalHold
      hold_events = NotificationLegalHoldEvent

      approved = policies.where(status: "Approved")
      created_events = policy_events.where(action: "Created")
      approval_events = policy_events.where(action: "Approved")
      release_events = hold_events.where(action: "Released")

      {
        assessed_at: Time.current,
        policy_count: policies.count,
        approved_policy_count: approved.count,
        approved_without_approval_event: approved.where.not(id: approval_events.select(:notification_retention_policy_id)).count,
        policies_without_creation_event: policies.where.not(id: created_events.select(:notification_retention_policy_id)).count,
        self_approved_policies: self_approved_count,
        active_hold_count: holds.active.count,
        released_hold_count: holds.where.not(released_at: nil).count,
        released_without_release_event: holds.where.not(released_at: nil)
          .where.not(id: release_events.select(:notification_legal_hold_id)).count,
        active_with_release_event: holds.active
          .where(id: release_events.select(:notification_legal_hold_id)).count,
        duplicate_release_event_holds: release_events.group(:notification_legal_hold_id)
          .having("COUNT(*) > 1").count.size,
        retention_audit_trigger_enabled: trigger_enabled?("infrastructure_notification_retention_events", "herga_retention_events_append_only"),
        legal_hold_audit_trigger_enabled: trigger_enabled?("infrastructure_notification_legal_hold_events", "herga_legal_hold_events_append_only"),
        disposal_enabled: false
      }
    end

    private

    # Compare the earliest creation actor against each approval actor without loading full event histories.
    # This detects inconsistent evidence; it does not prove an actor's real-world identity.
    def self_approved_count
      sql = <<~SQL
        SELECT COUNT(DISTINCT approved.notification_retention_policy_id)
        FROM infrastructure_notification_retention_events approved
        JOIN LATERAL (
          SELECT created.actor
          FROM infrastructure_notification_retention_events created
          WHERE created.notification_retention_policy_id = approved.notification_retention_policy_id
            AND created.action = 'Created'
          ORDER BY created.created_at ASC, created.id ASC
          LIMIT 1
        ) creator ON TRUE
        WHERE approved.action = 'Approved'
          AND lower(btrim(approved.actor)) = lower(btrim(creator.actor))
      SQL
      ActiveRecord::Base.connection.select_value(sql).to_i
    end

    def trigger_enabled?(table, trigger)
      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL, table, trigger
          SELECT EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgrelid = to_regclass(?)
              AND tgname = ?
              AND tgenabled IN ('O', 'A')
              AND NOT tgisinternal
          )
        SQL
      ])
      ActiveRecord::Base.connection.select_value(sql) == true
    end
  end
end
