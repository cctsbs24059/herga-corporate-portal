
# Controls the corporate application directory.
#
# Employees will use this page to browse and launch
# approved applications within the HERGA network.

class PortalApplicationsController < ApplicationController


  # Verify administrator membership before every action.
  before_action :require_portal_administrator




  # GET /portal_applications
  def index

    # Heading displayed on the page.
    @heading = "Corporate Applications"

    # Retrieve only applications that are active.
    # Sort them according to their configured position.
    @portal_applications = PortalApplication
                             .active_apps
                             .ordered

  end

  private

  def require_portal_administrator
    role = ActiveDirectoryAuthenticator.current_role(
      current_user.username
    )

    return if role == :admin

    redirect_to root_path,
                alert: "Administrator access is required."
  end

end
