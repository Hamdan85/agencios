require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # External host (e.g. an ngrok tunnel) the app is reachable at, read from
  # APP_HOST. Used to authorize the host, scope Action Cable origins, and build
  # absolute links in dev. Falls back to plain localhost when unset.
  app_host_url = ENV["APP_HOST"].present? ? URI.parse(ENV["APP_HOST"]) : nil

  # Allow requests for the configured external host alongside the localhost
  # defaults, plus any ngrok tunnel for convenience.
  config.hosts << app_host_url.host if app_host_url&.host
  config.hosts << /.*\.ngrok-free\.app/
  config.hosts << /.*\.ngrok\.io/

  # Action Cable forgery protection: accept the configured host's origin in
  # addition to localhost (the websocket is served same-origin at /cable).
  config.action_cable.allowed_request_origins = [
    %r{https?://localhost(:\d+)?},
    %r{https?://127\.0\.0\.1(:\d+)?},
    %r{https?://.*\.ngrok-free\.app},
    %r{https?://.*\.ngrok\.io}
  ]
  config.action_cable.allowed_request_origins << app_host_url.origin if app_host_url

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end

  # Change to :null_store to avoid any caching.
  config.cache_store = :memory_store

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Make template changes take effect immediately.
  config.action_mailer.perform_caching = false

  # Mailer previews (this app uses RSpec, so previews live under spec/).
  config.action_mailer.preview_paths << Rails.root.join("spec/mailers/previews").to_s

  # Set the host used by links generated in mailer templates. Prefer the
  # configured external host (e.g. ngrok) so emailed links resolve remotely.
  config.action_mailer.default_url_options =
    if app_host_url
      { host: app_host_url.host, protocol: app_host_url.scheme }.tap do |opts|
        opts[:port] = app_host_url.port if app_host_url.port && ![ 80, 443 ].include?(app_host_url.port)
      end
    else
      { host: "localhost", port: 3000 }
    end

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Highlight code that triggered redirect in logs.
  config.action_dispatch.verbose_redirect_logs = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
