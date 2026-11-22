
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

    # --------------------------------------------------------
    # Phase 2D.8.2.13
    # Infrastructure Notifications & Escalation
    #
    # Phase 2D.8.3.2
    # Notification Centre & Delivery Audit Trail
    # --------------------------------------------------------

    resources :notifications,
              only: [:index, :show]

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
