# frozen_string_literal: true

module Infrastructure
  class NotificationRetentionEvent < ApplicationRecord
    self.table_name = "infrastructure_notification_retention_events"

    belongs_to :notification_retention_policy,
               class_name: "Infrastructure::NotificationRetentionPolicy",
               inverse_of: :events

    validates :action, :actor, :to_status, :policy_version, presence: true
    validates :policy_version, numericality: { only_integer: true, greater_than: 0 }

    def readonly?
      persisted?
    end

    before_destroy { throw :abort }
  end
end
