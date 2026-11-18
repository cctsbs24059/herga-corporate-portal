
# frozen_string_literal: true

class InfrastructureIncident < ApplicationRecord
  TYPE_ICMP = "ICMP Connectivity"

  STATUSES = %w[Open Acknowledged Resolved].freeze
  SEVERITIES = %w[Warning Critical].freeze

  belongs_to :infrastructure_asset

  belongs_to :assigned_to,
             class_name: "User",
             optional: true

  belongs_to :acknowledged_by,
             class_name: "User",
             optional: true

  belongs_to :resolved_by,
             class_name: "User",
             optional: true

  has_many :infrastructure_incident_events,
           dependent: :destroy

  validates :incident_type, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }

  validates :first_detected_at, :last_observed_at,
            presence: true

  validates :consecutive_failures,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  scope :open_incidents, -> {
    where(status: "Open")
  }

  scope :unresolved, -> {
    where(status: %w[Open Acknowledged])
  }

  scope :resolved, -> {
    where(status: "Resolved")
  }

  scope :recent, -> {
    order(last_observed_at: :desc, id: :desc)
  }

  def unresolved?
    status.in?(%w[Open Acknowledged])
  end

  def acknowledged?
    status == "Acknowledged"
  end

  def resolved?
    status == "Resolved"
  end
end
