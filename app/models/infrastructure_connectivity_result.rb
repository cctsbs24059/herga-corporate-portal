
# frozen_string_literal: true

class InfrastructureConnectivityResult < ApplicationRecord
  belongs_to :infrastructure_asset

  belongs_to :infrastructure_monitoring_run,
             optional: true

  DNS_STATUSES = %w[
    Resolved
    Failed
  ].freeze

  ICMP_STATUSES = %w[
    Reachable
    Unreachable
    Unknown
  ].freeze

  validates :checked_at, presence: true

  validates :dns_status,
            inclusion: {
              in: DNS_STATUSES
            },
            allow_nil: true

  validates :icmp_status,
            inclusion: {
              in: ICMP_STATUSES
            },
            allow_nil: true

  validates :icmp_response_ms,
            numericality: {
              greater_than_or_equal_to: 0
            },
            allow_nil: true

  scope :recent, -> {
    order(checked_at: :desc)
  }

  scope :reachable, -> {
    where(icmp_status: "Reachable")
  }

  scope :unreachable, -> {
    where(icmp_status: "Unreachable")
  }

  scope :unknown, -> {
    where(icmp_status: "Unknown")
  }
end
