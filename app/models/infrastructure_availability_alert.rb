# frozen_string_literal: true

class InfrastructureAvailabilityAlert < ApplicationRecord
  STATUSES = %w[Active Acknowledged Cleared].freeze

  belongs_to :infrastructure_asset
  belongs_to :acknowledged_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :first_detected_at, :last_observed_at, :assessment_period_end, presence: true
  validates :threshold_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :last_availability_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validate :chronology

  scope :unresolved, -> { where(status: %w[Active Acknowledged]) }
  scope :recent, -> { order(last_observed_at: :desc, id: :desc) }

  def chronology
    if first_detected_at && last_observed_at && last_observed_at < first_detected_at
      errors.add(:last_observed_at, "cannot precede first detection")
    end
  end
end
