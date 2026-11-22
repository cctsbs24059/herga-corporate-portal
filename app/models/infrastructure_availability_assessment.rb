# frozen_string_literal: true

class InfrastructureAvailabilityAssessment < ApplicationRecord
  STATUSES = %w[MeetsThreshold BelowThreshold InsufficientData].freeze

  belongs_to :infrastructure_asset

  validates :period_start, :period_end, :assessment_status, presence: true
  validates :assessment_status, inclusion: { in: STATUSES }
  validates :threshold_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :total_checks, :reachable_checks, :unreachable_checks, :unknown_checks,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :period_end_after_start

  scope :latest_first, -> { order(period_end: :desc, id: :desc) }
  scope :breaches, -> { where(assessment_status: "BelowThreshold") }

  private

  def period_end_after_start
    return if period_start.blank? || period_end.blank? || period_end > period_start

    errors.add(:period_end, "must be after period start")
  end
end
