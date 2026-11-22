# frozen_string_literal: true

module Infrastructure
  class NotificationReconciler
    def call(now: Time.current)
      return { enabled: false, created: 0 } unless NotificationSettings.enabled?

      cutoff = NotificationSettings.activation_time
      count = 0
      InfrastructureIncident.where(first_detected_at: cutoff..now).find_each do |incident|
        count += emit("IncidentOpened", incident, incident.first_detected_at)
      end
      InfrastructureIncident.where(resolved_at: cutoff..now, status: "Resolved").find_each do |incident|
        count += emit("IncidentRecovered", incident, incident.resolved_at)
      end
      InfrastructureAvailabilityAlert.where(first_detected_at: cutoff..now).find_each do |alert|
        count += emit("AvailabilityBreached", alert, alert.first_detected_at)
      end
      InfrastructureAvailabilityAlert.where(cleared_at: cutoff..now, status: "Cleared").find_each do |alert|
        count += emit("AvailabilityRecovered", alert, alert.cleared_at)
      end
      eligible_at = now - NotificationSettings.escalation_minutes.minutes
      InfrastructureIncident.where(status: %w[Open Acknowledged], severity: "Critical")
        .where(first_detected_at: cutoff..eligible_at).find_each do |incident|
        count += emit("CriticalEscalation", incident, incident.first_detected_at)
      end
      { enabled: true, created: count }
    end

    private

    def emit(event_type, source, occurred_at)
      return 0 unless occurred_at

      key = "#{source.class.name}:#{source.id}:#{event_type}:#{NotificationSettings::RECIPIENT.downcase}"
      # Unique database index ensures idempotence even with concurrent schedulers.
      InfrastructureNotification.create_or_find_by!(event_key: key) do |record|
        record.source_type = source.class.name
        record.source_id = source.id
        record.event_type = event_type
        record.recipient = NotificationSettings::RECIPIENT
        record.occurred_at = occurred_at
        record.status = "Pending"
      end.tap { |record| return record.previously_new_record? ? 1 : 0 }
    end
  end
end
