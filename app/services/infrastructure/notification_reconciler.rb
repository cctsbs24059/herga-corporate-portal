
# frozen_string_literal: true

module Infrastructure
  class NotificationReconciler
    def call(now: Time.current)
      unless NotificationSettings.enabled?
        return {
          enabled: false,
          created: 0,
          recovered: 0
        }
      end

      cutoff = NotificationSettings.activation_time

      return {
        enabled: false,
        created: 0,
        recovered: 0
      } if cutoff.nil? || now < cutoff

      # Recover interrupted delivery attempts.
      recovery = NotificationRecovery.new.call(now: now)

      created = 0

      # --------------------------------------------------------
      # Incident opened
      # --------------------------------------------------------

      InfrastructureIncident
        .where(first_detected_at: cutoff..now)
        .find_each do |incident|

        created += emit(
          "IncidentOpened",
          incident,
          incident.first_detected_at
        )
      end

      # --------------------------------------------------------
      # Incident recovered
      # --------------------------------------------------------

      InfrastructureIncident
        .where(
          resolved_at: cutoff..now,
          status: "Resolved"
        )
        .find_each do |incident|

        created += emit(
          "IncidentRecovered",
          incident,
          incident.resolved_at
        )
      end

      # --------------------------------------------------------
      # Availability threshold breached
      # --------------------------------------------------------

      InfrastructureAvailabilityAlert
        .where(first_detected_at: cutoff..now)
        .find_each do |alert|

        created += emit(
          "AvailabilityBreached",
          alert,
          alert.first_detected_at
        )
      end

      # --------------------------------------------------------
      # Availability recovered
      # --------------------------------------------------------

      InfrastructureAvailabilityAlert
        .where(
          cleared_at: cutoff..now,
          status: "Cleared"
        )
        .find_each do |alert|

        created += emit(
          "AvailabilityRecovered",
          alert,
          alert.cleared_at
        )
      end

      # --------------------------------------------------------
      # Critical incident escalation
      # --------------------------------------------------------

      eligible_at =
        now - NotificationSettings.escalation_minutes.minutes

      if eligible_at >= cutoff
        InfrastructureIncident
          .where(
            status: %w[Open Acknowledged],
            severity: "Critical"
          )
          .where(first_detected_at: cutoff..eligible_at)
          .find_each do |incident|

          created += emit(
            "CriticalEscalation",
            incident,
            incident.first_detected_at
          )
        end
      end

      {
        enabled: true,
        created: created,
        recovered: recovery[:recovered]
      }
    end

    private

    def emit(event_type, source, occurred_at)
      return 0 unless occurred_at

      key = [
        source.class.name,
        source.id,
        event_type,
        NotificationSettings::RECIPIENT.downcase
      ].join(":")

      notification = InfrastructureNotification.create_or_find_by!(
        event_key: key
      ) do |record|

        record.source_type = source.class.name
        record.source_id = source.id
        record.event_type = event_type
        record.recipient = NotificationSettings::RECIPIENT
        record.occurred_at = occurred_at
        record.status = "Pending"
      end

      notification.previously_new_record? ? 1 : 0
    end
  end
end
