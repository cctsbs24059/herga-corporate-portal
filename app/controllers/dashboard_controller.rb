
# Controls the main HERGA Corporate Portal homepage.
#
# The index action retrieves information that will be
# displayed on the corporate dashboard.

class DashboardController < ApplicationController

  # GET /
  # GET /dashboard
  def index

    # Heading used by the dashboard.
    @heading = "HERGA Corporate Portal"

    # Retrieve active applications in display order.
    @portal_applications = PortalApplication
                             .active_apps
                             .ordered

    # Count the number of active applications.
    @application_count = @portal_applications.size

    # Announcements will be implemented in Phase 2.
    @announcement_count = 0

    # IT service monitoring will be implemented later.
    @service_count = 0

  end

end
