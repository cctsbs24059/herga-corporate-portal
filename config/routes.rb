
# Defines the URLs available within HERGA Corporate Portal.

Rails.application.routes.draw do

  # Keep any existing Devise routes here if authentication
  # has already been configured.
  #
  # Example:
  # devise_for :users

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

  # Rails health-check endpoint.
  # Used to verify that the Rails application is responding.
  get "up" => "rails/health#show", as: :rails_health_check

end
