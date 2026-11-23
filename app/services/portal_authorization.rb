
# frozen_string_literal: true

# HERGA Corporate Portal
# Phase 2E.1a - Centralised Role-Based Access Control
#
# This service defines application permissions independently
# of Active Directory authentication and Devise sessions.
#
# It does not query Active Directory or modify User records.
#
# Examples:
#
# PortalAuthorization.allowed?(
#   roles: [:auditor],
#   permission: :governance_evidence_read
# )
#
# PortalAuthorization.allowed?(
#   roles: [:infrastructure_admin],
#   permission: :infrastructure_manage
# )

class PortalAuthorization
  ROLE_PERMISSIONS = {
    portal_admin: %i[
      portal_read
      infrastructure_read
      infrastructure_manage
      governance_read
      governance_manage
      governance_evidence_read
      portal_applications_manage
    ],

    infrastructure_admin: %i[
      portal_read
      infrastructure_read
      infrastructure_manage
    ],

    security_admin: %i[
      portal_read
      infrastructure_read
      governance_read
      governance_manage
      governance_evidence_read
    ],

    auditor: %i[
      portal_read
      infrastructure_read
      governance_read
      governance_evidence_read
    ],

    employee: %i[
      portal_read
    ]
  }.transform_values { |permissions| permissions.freeze }.freeze

  ROLES = ROLE_PERMISSIONS.keys.freeze

  PERMISSIONS = ROLE_PERMISSIONS.values.flatten.uniq.freeze

  # Return true only when at least one recognised role
  # explicitly grants the requested permission.
  #
  # Unknown roles and permissions always return false.
  #
  # No implicit administrator fallback is permitted.
  def self.allowed?(roles:, permission:)
    return false unless PERMISSIONS.include?(permission)

    Array(roles).any? do |role|
      ROLE_PERMISSIONS.fetch(role, []).include?(permission)
    end
  end

  # Return the effective permissions for a set of roles.
  #
  # Multiple recognised roles contribute their permissions.
  # Unknown roles contribute nothing.
  def self.permissions_for(roles:)
    Array(roles)
      .flat_map { |role| ROLE_PERMISSIONS.fetch(role, []) }
      .uniq
      .freeze
  end

  # Return whether a role is recognised.
  def self.valid_role?(role)
    ROLES.include?(role)
  end

  # Return whether a permission is recognised.
  def self.valid_permission?(permission)
    PERMISSIONS.include?(permission)
  end
end
