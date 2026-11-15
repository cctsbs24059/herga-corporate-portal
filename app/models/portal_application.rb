# Represents an application registered in the HERGA Portal.
#
# Examples:
# - PXtool
# - Network Operations Centre
# - Configuration Management Database
# - IT Service Desk

class PortalApplication < ApplicationRecord

  # Require every application to have a name.
  validates :name, presence: true

  # Require a URL for launching the application.
  validates :url, presence: true

  # Only accept URLs beginning with HTTP or HTTPS.
  # This is basic format validation, not a security allowlist.
  validates :url, format: {
    with: /\Ahttps?:\/\/[^\s]+\z/i
  }

  # Return applications marked as active.
  scope :active_apps, -> {
    where(active: true)
  }

  # Sort applications by position, then name.
  scope :ordered, -> {
    order(:position, :name)
  }
  
end
