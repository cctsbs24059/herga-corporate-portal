
# frozen_string_literal: true

# HERGA Corporate Portal
# Application routing configuration

Rails.application.routes.draw do
  # ============================================================
  # Active Directory / Devise Authentication
  # ============================================================

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

  # ============================================================
  # Corporate Dashboard
  # ============================================================

  root "dashboard#index"

  get "dashboard", to: "dashboard#index"

  # ============================================================
  # Corporate Application Catalogue
  # ============================================================

  resources :portal_applications, only: [:index]

  # ============================================================
  # Active Directory Directory Management
  # ============================================================

  resources :directory_users, only: [:index, :show]
  resources :directory_groups, only: [:index, :show]
  resources :directory_computers, only: [:index, :show]

  # ============================================================
  # Infrastructure Asset Management
  # ============================================================

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

  # ============================================================
  # Infrastructure Incident Management
  # ============================================================

  resources :infrastructure_incidents, only: [:index, :show] do
    member do
      patch :acknowledge
      patch :assign
      patch :resolve
    end
  end

  # ============================================================
  # Phase 2D.7 - Infrastructure Monitoring Dashboard
  # Administrator-only access enforced by controller.
  # ============================================================

  namespace :infrastructure do
    get "monitoring",
        to: "monitoring#index",
        as: :monitoring
  end

  # ============================================================
  # Portal Administration
  # ============================================================

  namespace :admin do
    resources :portal_applications, except: [:show]
  end

  # ============================================================
  # Application Health
  # ============================================================

  get "up" => "rails/health#show",
      as: :rails_health_check
end
