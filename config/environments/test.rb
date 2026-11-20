
# The test environment is used exclusively to run the
# application's automated test suite.
#
# Test databases contain disposable test data.
# Never use production databases for automated tests.

Rails.application.configure do
  # Disable code reloading during tests.
  config.enable_reloading = false

  # Enable eager loading in CI.
  config.eager_load = ENV["CI"].present?

  # Serve public files with cache-control headers.
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=3600"
  }

  # Show detailed errors.
  config.consider_all_requests_local = true

  # Disable caching.
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable CSRF protection in tests.
  config.action_controller.allow_forgery_protection = false

  # Use local temporary storage for uploaded test files.
  config.active_storage.service = :test

  # Prevent real email delivery.
  config.action_mailer.delivery_method = :test

  config.action_mailer.default_url_options = {
    host: "example.com"
  }

  # Display deprecation notices.
  config.active_support.deprecation = :stderr

  # Validate before_action callback references.
  config.action_controller.raise_on_missing_callback_actions = true

  # ----------------------------------------------------------
  # SOLID QUEUE
  # ----------------------------------------------------------
  # Route Solid Queue models to the dedicated PostgreSQL
  # test queue database rather than the primary database.
  #
  # Database: herga_portal_test_queue
  # ----------------------------------------------------------

  config.solid_queue.connects_to = {
    database: {
      writing: :queue
    }
  }
end
