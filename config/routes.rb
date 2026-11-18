
# Defines the URLs available within HERGA Corporate Portal.

Rails.application.routes.draw do

  # Keep any existing Devise routes here if authentication
  # has already been configured.
  #
  # Example:
  # devise_for :users

    # Configure Devise authentication for the User model.
  # Use our custom sessions controller for HERGA.NET authentication.
  # HERGA.NET authentication
  # Only expose Devise session routes.
# ============================================================
# HERGA CORPORATE PORTAL
# Active Directory authentication routes
# ============================================================

  devise_for :users,
            skip: :all,
            controllers: {
              sessions: "users/sessions"
            }

  # Explicitly register the session endpoints.
  devise_scope :user do
    get    "users/sign_in",  to: "users/sessions#new",     as: :new_user_session
    post   "users/sign_in",  to: "users/sessions#create",  as: :user_session
    delete "users/sign_out", to: "users/sessions#destroy", as: :destroy_user_session
  end

  # Main corporate dashboard.
  # URL: http://localhost:3000/
  root "dashboard#index"

  # Alternative URL for the dashboard.
  # URL: http://localhost:3000/dashboard
  get "dashboard", to: "dashboard#index"

  # Corporate application catalogue.
  # Only the index action is available at this stage.
  #
  # URL: http://localhost:3000/portal_applications
  resources :portal_applications, only: [:index]





  # Active Directory User Management.
  # Read-only directory browsing.
  # Administrator access enforced by controller.

  resources :directory_users, only: [:index, :show]
  resources :directory_groups, only: [:index, :show]
  resources :directory_computers, only: [:index, :show]

  # Phase 2D - Infrastructure Asset Inventory

  # Phase 2D - Infrastructure Asset Inventory
  
  resources :infrastructure_assets do
    collection do
      post :sync_active_directory
      post :check_all_connectivity
    end

    member do
      patch :retire
      post :check_connectivity
    end
  end


  # Administration routes.
  namespace :admin do
    resources :portal_applications,
              except: [:show]
  end



  # Rails health-check endpoint.
  # Used to verify that the Rails application is responding.
  get "up" => "rails/health#show", as: :rails_health_check

end
