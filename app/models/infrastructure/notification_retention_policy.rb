# frozen_string_literal: true

module Infrastructure
  class NotificationRetentionPolicy < ApplicationRecord
    self.table_name = "infrastructure_notification_retention_policies"

    has_many :events, class_name: "Infrastructure::NotificationRetentionEvent",
             foreign_key: :notification_retention_policy_id, inverse_of: :notification_retention_policy,
             dependent: :restrict_with_exception

    validates :name, :reference, presence: true
    validates :reference, uniqueness: true
    validates :retention_days, inclusion: { in: 30..3650 }
    validates :status, inclusion: { in: %w[Draft Approved Suspended] }
    validates :version, numericality: { only_integer: true, greater_than: 0 }

    def disposal_authorized?
      false
    end
  end
end
