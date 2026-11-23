# frozen_string_literal: true

module Infrastructure
  class NotificationLegalHold < ApplicationRecord
    self.table_name = "infrastructure_notification_legal_holds"

    belongs_to :infrastructure_notification, class_name: "InfrastructureNotification"

    validates :reference, :reason, :placed_by, :placed_at, presence: true
    validates :reference, uniqueness: true

    scope :active, -> { where(released_at: nil) }

    def active?
      released_at.nil?
    end
  end
end
