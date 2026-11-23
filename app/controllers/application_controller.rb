
# frozen_string_literal: true

# HERGA Corporate Portal
# Phase 2E.1c - Application-Wide RBAC Integration
#
# Responsibilities:
# - Require Devise authentication.
# - Verify current Active Directory group membership.
# - Expose role-aware permission helpers.
# - Preserve existing administrator checks.
# - Fail closed when AD access cannot be verified.
#
# Roles are never trusted from browser parameters,
# session data or the local User.admin field.

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :verify_active_directory_access

  helper_method :current_portal_roles,
                :current_portal_role,
                :portal_admin?,
                :portal_employee?,
                :portal_can?,
                :portal_has_role?

  private

  # Retrieve the current user's live AD roles.
  #
  # Cache the result for the current request only.
  # Do not use ||= because nil must also be cached.
  def current_portal_roles
    return nil unless user_signed_in?

    unless instance_variable_defined?(:@current_portal_roles)
      @current_portal_roles =
        ActiveDirectoryAuthenticator.current_roles(
          current_user.username
        )
    end

    @current_portal_roles
  end

  # Legacy compatibility for code expecting one role.
  #
  # The full role array remains authoritative.
  def current_portal_role
    roles = current_portal_roles

    return nil if roles.nil? || roles.empty?
    return :admin if roles.include?(:portal_admin)

    :employee
  end

  # Check that Active Directory still authorises access.
  #
  # A failed lookup or empty role set terminates the
  # existing session and redirects to the login page.
  def verify_active_directory_access
    return unless user_signed_in?

    roles = current_portal_roles

    return if roles.is_a?(Array) &&
              roles.any? { |role| PortalAuthorization.valid_role?(role) }

    sign_out(current_user)

    redirect_to(
      new_user_session_path,
      alert: "Your HERGA.NET directory access could not be verified."
    )
  end

  # Check whether the user holds a particular role.
  def portal_has_role?(role)
    roles = current_portal_roles

    roles.is_a?(Array) && roles.include?(role)
  end

  # Preserve existing portal administrator checks.
  def portal_admin?
    portal_has_role?(:portal_admin)
  end

  # Preserve the legacy helper name.
  #
  # This represents access to the ordinary portal,
  # not necessarily membership of HERGA-Portal-Users.
  def portal_employee?
    portal_can?(:portal_read)
  end

  # Check an application permission using the central
  # Phase 2E.1a authorisation matrix.
  def portal_can?(permission)
    roles = current_portal_roles

    return false unless roles.is_a?(Array)

    PortalAuthorization.allowed?(
      roles: roles,
      permission: permission
    )
  end

  # Require a specific application permission.
  #
  # Example:
  # before_action -> {
  #   require_portal_permission(:governance_evidence_read)
  # }
  def require_portal_permission(permission)
    return if portal_can?(permission)

    redirect_to(
      root_path,
      alert: "You do not have permission to perform this action."
    )
  end

  # Backward-compatible administrator enforcement.
  #
  # Existing controllers using this method remain
  # restricted to the HERGA portal administrator role.
  def require_portal_administrator
    return if portal_admin?

    redirect_to(
      root_path,
      alert: "Administrator access is required."
    )
  end
end
