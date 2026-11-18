
# frozen_string_literal: true

class InfrastructureIncidentEvent < ApplicationRecord
  EVENT_TYPES = %w[
    Created
    Acknowledged
    Assigned
    Reassigned
    Resolved
    Recovered
    Retired
  ].freeze

  belongs_to :infrastructure_incident
  belongs_to :user, optional: true

  validates :event_type, inclusion: {
    in: EVENT_TYPES
  }

  scope :recent, -> {
    order(created_at: :desc, id: :desc)
  }
end
