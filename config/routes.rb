
# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
# Application Routing Configuration
# ============================================================

Rails.application.routes.draw do

  # ==========================================================
  # 1. AUTHENTICATION - DEVISE / ACTIVE DIRECTORY
  # ==========================================================

  devise_for :users,
             skip: :all,
             controllers: {
               sessions: "users/sessions"
             }

  devise_scope :user do

    get "users/sign_in",
        to: "users/sessions#new",
        as: :new_user_session

    post "users/sign_in",
         to: "users/sessions#create",
         as: :user_session

    delete "users/sign_out",
           to: "users/sessions#destroy",
           as: :destroy_user_session

  end

  # ==========================================================
  # 2. MAIN DASHBOARD
  # ==========================================================

  root "dashboard#index"

  get "dashboard",
      to: "dashboard#index"

  # ==========================================================
  # 3. CORPORATE APPLICATION DIRECTORY
  # ==========================================================

  resources :portal_applications,
            only: [:index]

  # ==========================================================
  # 4. ACTIVE DIRECTORY
  # ==========================================================

  resources :directory_users,
            only: [:index, :show]

  resources :directory_groups,
            only: [:index, :show]

  resources :directory_computers,
            only: [:index, :show]

  # ==========================================================
  # 5. INFRASTRUCTURE ASSET MANAGEMENT
  # ==========================================================

  resources :infrastructure_assets do

    collection do

      post :sync_active_directory

      post :check_all_connectivity

    end

    member do

      get :history

      patch :retire

      post :check_connectivity

    end

  end

  # ==========================================================
  # 6. INFRASTRUCTURE INCIDENT MANAGEMENT
  # ==========================================================

  resources :infrastructure_incidents,
            only: [:index, :show] do

    member do

      patch :acknowledge

      patch :assign

      patch :resolve

    end

  end

  # ==========================================================
  # 7. INFRASTRUCTURE MONITORING & REPORTING
  # ==========================================================

  namespace :infrastructure do

    # --------------------------------------------------------
    # Phase 2D.8.2.6
    # Infrastructure Monitoring Dashboard
    # --------------------------------------------------------

    get "monitoring",
        to: "monitoring#index",
        as: :monitoring

    # --------------------------------------------------------
    # Phase 2D.8.2.3 - 2D.8.2.5
    # Infrastructure Availability Reporting
    # --------------------------------------------------------

    get "availability",
        to: "availability#index",
        as: :availability

    # --------------------------------------------------------
    # Phase 2D.8.2.7
    # Infrastructure Availability Alert Management
    # --------------------------------------------------------

    resources :availability_alerts,
              only: [:index, :show] do

      member do

        patch :acknowledge

      end

    end

    # --------------------------------------------------------
    # Phase 2D.8.2.10
    # Operational Audit & Reporting
    # --------------------------------------------------------

    get "operational_reports",
        to: "operational_reports#index",
        as: :operational_reports

    # --------------------------------------------------------
    # Phase 2D.8.2.11
    # Infrastructure Monitoring Analytics & Trends
    # --------------------------------------------------------

    get "analytics",
        to: "analytics#index",
        as: :analytics

    # --------------------------------------------------------
    # Phase 2D.8.2.12
    # Infrastructure Executive Dashboard
    # --------------------------------------------------------

    get "executive_dashboard",
        to: "executive_dashboard#index",
        as: :executive_dashboard

    # ========================================================
    # NOTIFICATION MANAGEMENT
    # ========================================================
    #
    # IMPORTANT ROUTING RULE:
    #
    # All static notification routes must be declared
    # before the dynamic notifications resource.
    #
    # This prevents Rails interpreting:
    #
    #   /notifications/reports
    #   /notifications/analytics
    #   /notifications/job_failures
    #
    # as notification record IDs.
    #
    # ========================================================

    # --------------------------------------------------------
    # Phase 2D.8.4.3.4
    # Advanced Notification Failure Investigation
    #
    # Administrator-only access enforced by controller
    # Read-only failure history and investigation details
    # --------------------------------------------------------

    get "notifications/job_failures",
        to: "notification_job_failures#index",
        as: :notification_job_failures

    get "notifications/job_failures/:id",
        to: "notification_job_failures#show",
        as: :notification_job_failure,
        constraints: { id: /\d+/ }

    # --------------------------------------------------------
    # Phase 2D.8.4.3.5
    # Notification Operational Analytics & Trends
    #
    # Administrator-only access enforced by controller
    # Read-only analytics and reporting dashboard
    # --------------------------------------------------------

    get "notifications/analytics",
        to: "notification_analytics#index",
        as: :notification_analytics

    # --------------------------------------------------------
    # Phase 2D.8.4.3.6
    # Notification Reporting & CSV Export
    #
    # Administrator-only access enforced by controller
    # Read-only reporting and CSV downloads
    #
    # Supported report types:
    #
    #   history   - Notification history
    #   attempts  - Delivery attempt audit
    #   analytics - Notification analytics summary
    #
    # Reporting periods:
    #
    #   24h
    #   7d
    #   30d
    #   90d
    #
    # Example:
    #
    # /infrastructure/notifications/reports
    #
    # CSV export:
    #
    # /infrastructure/notifications/reports.csv?type=history
    #
    # --------------------------------------------------------

    get "notifications/reports",
        to: "notification_reports#index",
        as: :notification_reports

    # --------------------------------------------------------
    # Phase 2D.8.2.13
    # Infrastructure Notifications & Escalation
    #
    # Phase 2D.8.3.2
    # Notification Centre & Delivery Audit Trail
    #
    # Phase 2D.8.4.3.3
    # Notification Processing Diagnostics
    #
    # SECURITY HARDENING:
    #
    # Restrict notification IDs to numeric values.
    #
    # Prevent malformed URLs such as:
    #
    #   /notifications/reports**
    #
    # from reaching NotificationsController#show.
    #
    # --------------------------------------------------------

    resources :notifications,
              only: [:index, :show],
              constraints: { id: /\d+/ }

  end

  # ==========================================================
  # 8. PORTAL ADMINISTRATION
  # ==========================================================

  namespace :admin do

    resources :portal_applications,
              except: [:show]

  end

  # ==========================================================
  # 9. APPLICATION HEALTH CHECK
  # ==========================================================

  get "up",
      to: "rails/health#show",
      as: :rails_health_check

end
