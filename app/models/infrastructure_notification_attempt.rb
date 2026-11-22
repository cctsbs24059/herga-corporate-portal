# frozen_string_literal: true

class InfrastructureNotificationAttempt < ApplicationRecord
  belongs_to :infrastructure_notification
  validates :status, inclusion: { in: %w[Accepted Unknown] }
  validates :attempted_at, presence: true
end
