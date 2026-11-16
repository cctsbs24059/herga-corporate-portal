
# ============================================================
# HERGA CORPORATE PORTAL
# ApplicationController
# ============================================================
#
# Purpose:
# This is the base controller for the HERGA Corporate Portal.
#
# It provides:
#   1. Devise authentication for all portal pages.
#   2. Active Directory authorisation through HERGA.NET.
#   3. Verification of current AD security-group membership.
#   4. Automatic sign-out when directory access is denied.
#   5. Administrator permission checks.
#
# Active Directory configuration:
#
#   Domain:             HERGA.NET
#   Domain Controller:  csi.herga.net
#   Employee Group:     HERGA-Portal-Users
#   Administrator Group: HERGA-Portal-Admins
#
# Authentication is handled by Devise and the custom
# ActiveDirectoryAuthenticator service.
#
# The controller never receives or stores AD passwords.
#
# ============================================================

class ApplicationController < ActionController::Base

  # ----------------------------------------------------------
  # 1. BROWSER COMPATIBILITY
  # ----------------------------------------------------------
  #
  # Retain the Rails 8 browser compatibility policy.
  #
  # This allows modern browsers supporting current Rails
  # frontend functionality.

  allow_browser versions: :modern


  # ----------------------------------------------------------
  # 2. REQUIRE USER AUTHENTICATION
  # ----------------------------------------------------------
  #
  # Devise checks whether the current request has a valid
  # authenticated user session.
  #
  # Unauthenticated users are redirected to the login page.
  #
  # Devise's own SessionsController inherits from
  # DeviseController, so this callback does not interfere
  # with displaying the login form.

  before_action :authenticate_user!


  # ----------------------------------------------------------
  # 3. VERIFY ACTIVE DIRECTORY ACCESS
  # ----------------------------------------------------------
  #
  # After Devise validates the session, verify that the
  # employee still belongs to an authorised AD group.
  #
  # Accepted groups:
  #
  #   HERGA-Portal-Users
  #   HERGA-Portal-Admins
  #
  # The ActiveDirectoryAuthenticator service performs
  # the membership lookup using LDAPS.
  #
  # If AD cannot verify membership, access is denied.

  before_action :verify_active_directory_access


  # ----------------------------------------------------------
  # 4. EXPOSE AUTHORISATION HELPERS TO VIEWS
  # ----------------------------------------------------------
  #
  # Allows Rails views and navigation partials to check:
  #
  #   portal_admin?
  #   portal_employee?
  #
  # Example:
  #
  #   <% if portal_admin? %>
  #     <%= link_to "Administration",
  #                 admin_portal_applications_path %>
  #   <% end %>
  #
  # These helpers control what is displayed.
  # Controller-level checks still enforce permissions.

  helper_method :portal_admin?, :portal_employee?


  # ----------------------------------------------------------
  # 5. PRIVATE SECURITY METHODS
  # ----------------------------------------------------------

  private


  # ----------------------------------------------------------
  # VERIFY ACTIVE DIRECTORY MEMBERSHIP
  # ----------------------------------------------------------
  #
  # Called automatically before each authenticated request.
  #
  # The service returns:
  #
  #   :admin     - member of HERGA-Portal-Admins
  #   :employee  - member of HERGA-Portal-Users
  #   nil        - no permission or AD lookup failure
  #
  # A nil result causes the session to be terminated.
  #
  # This is intentionally fail-closed.

  def verify_active_directory_access

    # Devise handles unauthenticated requests.
    return unless user_signed_in?

    # Retrieve the current user's AD permissions.
    #
    # Memoise the result for this request so that
    # navigation helpers do not repeat LDAP searches.
    role = current_portal_role

    # Permit the request when AD confirms membership.
    return if role == :admin || role == :employee

    # Remove the existing Devise session.
    sign_out(current_user)

    # Redirect to the HERGA login page.
    redirect_to new_user_session_path,
                alert: "Your HERGA.NET directory access could not be verified."

  end


  # ----------------------------------------------------------
  # RETRIEVE CURRENT AD ROLE
  # ----------------------------------------------------------
  #
  # Consult Active Directory using the username stored
  # in the local PostgreSQL User record.
  #
  # The AD service uses the configured read-only service
  # account for membership lookups.
  #
  # Results are cached only for the current request.
  #
  # A new request triggers a fresh membership check.

  def current_portal_role

    return nil unless user_signed_in?

    @current_portal_role ||=
      ActiveDirectoryAuthenticator.current_role(
        current_user.username
      )

  end


  # ----------------------------------------------------------
  # CHECK ADMINISTRATOR ACCESS
  # ----------------------------------------------------------
  #
  # Returns true only when Active Directory confirms that
  # the user belongs to HERGA-Portal-Admins.
  #
  # Used by:
  # - Navigation menus
  # - Dashboard administration links
  # - Administrative controllers

  def portal_admin?

    current_portal_role == :admin

  end


  # ----------------------------------------------------------
  # CHECK EMPLOYEE ACCESS
  # ----------------------------------------------------------
  #
  # Both administrators and employees can access ordinary
  # corporate portal functionality.

  def portal_employee?

    [:employee, :admin].include?(current_portal_role)

  end


  # ----------------------------------------------------------
  # ENFORCE ADMINISTRATOR ACCESS
  # ----------------------------------------------------------
  #
  # Administrative controllers should call:
  #
  #   before_action :require_portal_administrator
  #
  # A user without administrator permissions is redirected
  # to the corporate dashboard.
  #
  # This is a server-side security check.

  def require_portal_administrator

    # Permit authorised administrators.
    return if portal_admin?

    # Prevent non-administrators from accessing
    # application management functions.
    redirect_to root_path,
                alert: "Administrator access is required."

  end

end
