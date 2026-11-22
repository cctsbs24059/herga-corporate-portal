# frozen_string_literal: true

class InfrastructureNotification < ApplicationRecord
  STATUSES = %w[Pending Sending Accepted Unknown].freeze
  EVENTS = %w[IncidentOpened IncidentRecovered AvailabilityBreached AvailabilityRecovered CriticalEscalation].freeze

  has_many :infrastructure_notification_attempts, dependent: :restrict_with_exception
  validates :event_key, :source_type, :source_id, :event_type, :recipient, :occurred_at, presence: true
  validates :event_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :event_type, inclusion: { in: EVENTS }
  validates :recipient, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
