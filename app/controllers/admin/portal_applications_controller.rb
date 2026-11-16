
# Manages the applications registered in HERGA Corporate Portal.
#
# Administration functions include:
# - Viewing registered applications
# - Creating applications
# - Editing application information
# - Activating and deactivating applications
# - Removing applications
#
# The controller is intentionally separate from the
# employee-facing PortalApplicationsController.

module Admin
  class PortalApplicationsController < ApplicationController

    # SECURITY:
    # Do not expose this controller without authentication
    # and administrator authorisation.
    #
    # Authentication will be configured before enabling
    # the administration routes.

    # Retrieve the selected application before actions
    # that require an existing database record.
    before_action :set_portal_application,
                  only: [:edit, :update, :destroy]

    # GET /admin/portal_applications
    #
    # Display all applications, including inactive ones.
    def index
      @portal_applications = PortalApplication.ordered
    end

    # GET /admin/portal_applications/new
    #
    # Prepare an empty application record.
    def new
      @portal_application = PortalApplication.new
    end

    # POST /admin/portal_applications
    #
    # Create an application using submitted form values.
    def create
      @portal_application =
        PortalApplication.new(portal_application_params)

      if @portal_application.save
        redirect_to admin_portal_applications_path,
                    notice: "Application created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /admin/portal_applications/:id/edit
    #
    # Display the edit form.
    def edit
    end

    # PATCH /admin/portal_applications/:id
    #
    # Update an existing application.
    def update
      if @portal_application.update(portal_application_params)
        redirect_to admin_portal_applications_path,
                    notice: "Application updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/portal_applications/:id
    #
    # Remove an application from the directory.
    def destroy
      @portal_application.destroy!

      redirect_to admin_portal_applications_path,
                  notice: "Application removed successfully.",
                  status: :see_other
    end

    private

    # Find the application requested in the URL.
    def set_portal_application
      @portal_application =
        PortalApplication.find(params[:id])
    end

    # Allow only approved application attributes.
    #
    # This prevents arbitrary database fields from being
    # modified through the submitted form.
    def portal_application_params
      params.require(:portal_application).permit(
        :name,
        :description,
        :url,
        :category,
        :icon,
        :active,
        :position
      )
    end

  end
end
