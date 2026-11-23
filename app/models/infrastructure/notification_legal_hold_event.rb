# frozen_string_literal: true

module Infrastructure
  class NotificationLegalHoldEvent < ApplicationRecord
    self.table_name = "infrastructure_notification_legal_hold_events"
    belongs_to :notification_legal_hold, class_name: "Infrastructure::NotificationLegalHold"

    validates :action, inclusion: { in: %w[Placed Released] }
    validates :actor, :justification, presence: true
    validate :immutable_after_creation, on: :update

    def readonly?
      persisted?
    end

    before_destroy { throw :abort }

    private

    def immutable_after_creation
      errors.add(:base, "Audit events are immutable")
    end
  end
end
