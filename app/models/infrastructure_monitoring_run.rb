
# frozen_string_literal: true

class InfrastructureMonitoringRun < ApplicationRecord
  STATUSES = %w[
    Queued
    Running
    Completed
    Failed
  ].freeze

  has_many :infrastructure_connectivity_results,
           dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  validates :total_assets,
            :processed_assets,
            :reachable_assets,
            :unreachable_assets,
            :unknown_assets,
            :failed_checks,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  scope :recent, -> { order(created_at: :desc) }

  scope :active, -> {
    where(status: %w[Queued Running])
  }

  def queued?
    status == "Queued"
  end

  def running?
    status == "Running"
  end

  def completed?
    status == "Completed"
  end

  def failed?
    status == "Failed"
  end

  def progress_percentage
    return 0 if total_assets.zero?

    ((processed_assets.to_f / total_assets) * 100).round(1)
  end
end
