
# Controls the main HERGA Corporate Portal homepage.
#
# Displays registered corporate applications, dashboard
# statistics, announcements and service information.
#
# Existing Active Directory authentication and
# authorisation are inherited from ApplicationController.

class DashboardController < ApplicationController

  # GET /
  # GET /dashboard
  def index

    # Corporate dashboard heading.
    @heading = "HERGA Corporate Portal"

    # --------------------------------------------------
    # EXISTING APPLICATION FUNCTIONALITY
    # --------------------------------------------------

    # Retrieve active applications in display order.
    @portal_applications = PortalApplication
                             .active_apps
                             .ordered

    # Count active applications.
    @application_count = @portal_applications.size

    # Announcements will be implemented in Phase 2.
    @announcement_count = 0

    # IT service monitoring will be implemented later.
    @service_count = 0

    # --------------------------------------------------
    # DASHBOARD INFORMATION
    # --------------------------------------------------

    @page_title = "Corporate Dashboard"

    @current_time = Time.current

    # --------------------------------------------------
    # INFRASTRUCTURE MODULES
    # --------------------------------------------------

    # These are planned modules.
    # No live Active Directory queries are made here.

    @infrastructure_modules = [
      {
        title: "Active Directory Users",
        description: "Browse domain user accounts and account status.",
        icon: "bi-people",
        status: "Planned"
      },
      {
        title: "Security Groups",
        description: "Review Active Directory security groups and memberships.",
        icon: "bi-shield-lock",
        status: "Planned"
      },
      {
        title: "Domain Computers",
        description: "Browse domain-joined computers and workstations.",
        icon: "bi-pc-display",
        status: "Planned"
      },
      {
        title: "Infrastructure Servers",
        description: "View corporate servers and infrastructure information.",
        icon: "bi-hdd-network",
        status: "Planned"
      },
      {
        title: "Security & Audit",
        description: "Review portal security events and audit records.",
        icon: "bi-journal-text",
        status: "Planned"
      }
    ]

  end

end
