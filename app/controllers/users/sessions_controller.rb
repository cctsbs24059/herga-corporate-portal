
# Handles HERGA Active Directory sign-in and sign-out.
#
# Devise manages the Rails session.
# Active Directory validates the submitted credentials.

module Users
  class SessionsController < Devise::SessionsController
    # Display the sign-in form.
    def new
      super
    end

    # Authenticate against HERGA.NET.
    def create
      login = params.dig(:user, :username).to_s
      password = params.dig(:user, :password).to_s

      # Validate credentials and AD group membership.
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

      # Create or update the local profile.
      #
      # The AD username is the account's stable lookup key
      # within this single-domain implementation.
      user = User.find_or_initialize_by(
        username: identity.username
      )

      user.assign_attributes(
        email: identity.email,
        display_name: identity.display_name,
        ad_dn: identity.dn,
        admin: identity.admin
      )

      user.save!

      # Regenerate the session identifier before sign-in.
      reset_session

      # Sign in using Devise/Warden.
      sign_in(:user, user)

      redirect_to root_path,
                  notice: "Welcome to HERGA Corporate Portal."
    end

    # Devise handles session termination.
    def destroy
      super
    end
  end
end
