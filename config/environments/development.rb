
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here take precedence over config/application.rb.

  # Reload application code without restarting the server.
  config.enable_reloading = true

  # Do not eager load application code during development.
  config.eager_load = false

  # Display detailed error reports.
  config.consider_all_requests_local = true

  # Enable server timing information.
  config.server_timing = true

  # Development caching configuration.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.public_file_server.headers = {
      "cache-control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false
  end

  # Cache configuration.
  config.cache_store = :memory_store

  # Active Storage.
  config.active_storage.service = :local

  # Action Mailer.
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false

  config.action_mailer.default_url_options = {
    host: "localhost",
    port: 3000
  }

  # Log deprecation notices.
  config.active_support.deprecation = :log

  # Report pending database migrations.
  config.active_record.migration_error = :page_load

  # Log database queries with source information.
  config.active_record.verbose_query_logs = true
  config.active_record.query_log_tags_enabled = true

  # ----------------------------------------------------------
  # HERGA Portal - Persistent Background Job Processing
  # ----------------------------------------------------------

  config.active_job.queue_adapter = :solid_queue

  config.solid_queue.connects_to = {
    database: { writing: :queue }
  }

  # Show where jobs are enqueued.
  config.active_job.verbose_enqueue_logs = true

  # ----------------------------------------------------------
  # Development Diagnostics
  # ----------------------------------------------------------

  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logging for static asset requests.
  config.assets.quiet = true

  # Annotate rendered views with their source filenames.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Validate controller callback action names.
  config.action_controller.raise_on_missing_callback_actions = true

  # Uncomment to report missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Uncomment to allow Action Cable requests from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Uncomment to enable RuboCop autocorrection for generators.
  # config.generators.apply_rubocop_autocorrect_after_generate!

  # This code goes into .env file and uses the IPs in BIND_IPS
  ENV.fetch("BIND_IPS", "").split(",").each do |ip|
    config.hosts << ip.strip
  end
end
