
# frozen_string_literal: true

# HERGA Corporate Portal
# Phase 2E.1c - Active Directory RBAC Login
#
# Devise manages the authenticated Rails session.
# Active Directory validates credentials and group membership.
#
# The local User record stores identity attributes only.
# Live authorisation always uses Active Directory.

module Users
  class SessionsController < Devise::SessionsController
    def new
      super
    end

    def create
      login = params.dig(:user, :username).to_s
      password = params.dig(:user, :password).to_s

      identity = ActiveDirectoryAuthenticator.authenticate(
        login,
        password
      )

      unless identity
        flash.now[:alert] =
          "Invalid credentials or insufficient access."

        self.resource = User.new

        return render :new, status: :unprocessable_entity
      end

      # Defence in depth: require a recognised RBAC role.
      #
      # The authenticator already enforces this, but
      # the controller independently checks the result.
      roles = identity.roles

      unless roles.is_a?(Array) &&
             roles.any? { |role| PortalAuthorization.valid_role?(role) }

        flash.now[:alert] =
          "Your account does not have portal access."

        self.resource = User.new

        return render :new, status: :unprocessable_entity
      end

      user = User.find_or_initialize_by(
        username: identity.username
      )

      # The admin column is retained for compatibility.
      # It must not be used for live authorisation.
      user.assign_attributes(
        email: identity.email,
        display_name: identity.display_name,
        ad_dn: identity.dn,
        admin: roles.include?(:portal_admin)
      )

      user.save!

      # Regenerate the Rails session before signing in.
      reset_session

      sign_in(:user, user)

      redirect_to(
        root_path,
        notice: "Welcome to HERGA Corporate Portal."
      )
    end

    def destroy
      super
    end
  end
end
