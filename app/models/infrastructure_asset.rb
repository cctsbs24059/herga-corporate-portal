
# frozen_string_literal: true

class InfrastructureAsset < ApplicationRecord
  ASSET_TYPES = [
    "Windows Server",
    "Linux Server",
    "Hyper-V Host",
    "Virtual Machine",
    "Network Switch",
    "Router",
    "Firewall",
    "NAS",
    "Storage System",
    "Other"
  ].freeze

  ENVIRONMENTS = [
    "Production",
    "Development",
    "Test",
    "Disaster Recovery",
    "Other"
  ].freeze

  STATUSES = [
    "Active",
    "Maintenance",
    "Retired"
  ].freeze

  SOURCES = [
    "Manual",
    "Active Directory"
  ].freeze

  validates :hostname, presence: true, length: { maximum: 255 }
  validates :fqdn, length: { maximum: 255 }
  validates :ip_address, length: { maximum: 45 }

  validates :asset_type, inclusion: { in: ASSET_TYPES }
  validates :environment, inclusion: { in: ENVIRONMENTS }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }

  validates :ad_object_guid,
            uniqueness: true,
            allow_blank: true

  validates :fqdn,
            uniqueness: { case_sensitive: false },
            allow_blank: true

  validate :valid_ip_address

  before_validation :normalise_identifiers

  scope :active_assets, -> { where(status: "Active") }
  scope :ordered, -> { order(:hostname, :id) }
  scope :manual_assets, -> { where(source: "Manual") }
  scope :directory_assets, -> { where(source: "Active Directory") }

  def directory_managed?
    source == "Active Directory"
  end

  def manually_registered?
    source == "Manual"
  end

  private

  def normalise_identifiers
    self.hostname = hostname.to_s.strip.upcase
    self.fqdn = fqdn.to_s.strip.downcase.presence
    self.ip_address = ip_address.to_s.strip.presence
    self.ad_object_guid = ad_object_guid.to_s.strip.downcase.presence
  end

  def valid_ip_address
    return if ip_address.blank?

    require "ipaddr"
    IPAddr.new(ip_address)
  rescue IPAddr::InvalidAddressError
    errors.add(:ip_address, "must be a valid IPv4 or IPv6 address")
  end
end
