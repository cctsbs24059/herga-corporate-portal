
# frozen_string_literal: true

# ================================================================
# HERGA CORPORATE PORTAL
# Application Administration Controller
#
# Security:
# - Devise authentication inherited from ApplicationController
# - Active Directory access verification inherited
# - Live AD-backed RBAC permission enforcement
# - Fail-closed authorization
#
# Required permission:
#   :portal_applications_manage
#
# Supported actions:
# - List registered applications
# - Create applications
# - Edit application information
# - Activate/deactivate applications
# - Remove applications
#
# This controller is separate from the employee-facing
# PortalApplicationsController.
# ================================================================

module Admin
  class PortalApplicationsController < ApplicationController

    # ============================================================
    # AUTHORIZATION
    # ============================================================

    # Require the application management permission for ALL
    # controller actions, including actions added in the future.
    #
    # The permission is resolved through the authenticated user's
    # current Active Directory roles.
    #
    # Do not use current_user.admin? for authorization.

    before_action -> {
      require_portal_permission(:portal_applications_manage)
    }

    # ============================================================
    # RECORD LOOKUP
    # ============================================================

    # Retrieve an existing application only after authorization.

    before_action :set_portal_application,
                  only: %i[edit update destroy]

    # ============================================================
    # INDEX
    # GET /admin/portal_applications
    # ============================================================

    # Display all registered applications, including inactive ones.

    def index
      @portal_applications = PortalApplication.ordered
    end

    # ============================================================
    # NEW
    # GET /admin/portal_applications/new
    # ============================================================

    def new
      @portal_application = PortalApplication.new
    end

    # ============================================================
    # CREATE
    # POST /admin/portal_applications
    # ============================================================

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

    # ============================================================
    # EDIT
    # GET /admin/portal_applications/:id/edit
    # ============================================================

    def edit
      # The application is loaded by set_portal_application.
    end

    # ============================================================
    # UPDATE
    # PATCH/PUT /admin/portal_applications/:id
    # ============================================================

    def update
      if @portal_application.update(portal_application_params)
        redirect_to admin_portal_applications_path,
                    notice: "Application updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # ============================================================
    # DESTROY
    # DELETE /admin/portal_applications/:id
    # ============================================================

    def destroy
      @portal_application.destroy!

      redirect_to admin_portal_applications_path,
                  notice: "Application removed successfully.",
                  status: :see_other
    end

    # ============================================================
    # PRIVATE METHODS
    # ============================================================

    private

    # ------------------------------------------------------------
    # Find the application requested in the URL.
    # ------------------------------------------------------------

    def set_portal_application
      @portal_application =
        PortalApplication.find(params[:id])
    end

    # ------------------------------------------------------------
    # Strong Parameters
    #
    # Only explicitly approved application attributes can be
    # submitted through the administration interface.
    # ------------------------------------------------------------

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
