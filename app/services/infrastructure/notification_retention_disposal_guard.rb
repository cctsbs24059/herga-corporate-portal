# frozen_string_literal: true

module Infrastructure
  # Assessment-only safeguard; no disposal action is implemented.
  class NotificationRetentionDisposalGuard
    def initialize(notification:, policy:)
      @notification = notification
      @policy = policy
    end

    def assessment
      reasons = ["Automated disposal is not implemented or authorised"]
      reasons << "Policy is not approved" unless @policy.status == "Approved"
      reasons << "Protected operational status" if %w[Pending Sending Unknown].include?(@notification.status)
      if NotificationLegalHold.active.exists?(infrastructure_notification_id: @notification.id)
        reasons << "Active legal hold"
      end
      { disposal_authorized: false, reasons: reasons.freeze }.freeze
    end
  end
end
