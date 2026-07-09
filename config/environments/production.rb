# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on Upuai Cloud object storage (S3-compatible). Falls
  # back to local disk only if the bucket service is not linked (no S3_BUCKET).
  config.active_storage.service = ENV['S3_BUCKET'].present? ? :upuai : :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = '/up'

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque

  # Host used by links generated in mailer templates — derived from APP_HOST.
  _app_uri = URI.parse(ENV.fetch('APP_HOST', 'http://localhost:3000'))
  config.action_mailer.default_url_options = { host: _app_uri.host, protocol: _app_uri.scheme }
  config.action_mailer.asset_host = "#{_app_uri.scheme}://#{_app_uri.host}"

  # Outgoing SMTP — sourced from encrypted credentials (`credentials.smtp`),
  # with ENV overrides as a fallback per field. Only enabled when an address
  # resolves, so the app boots cleanly before email delivery is wired.
  config.action_mailer.delivery_method = :smtp
  smtp = Rails.application.credentials.smtp || {}
  smtp_address = smtp[:address].presence || ENV['SMTP_ADDRESS'].presence
  if smtp_address.present?
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: smtp_address,
      port: (smtp[:port] || ENV.fetch('SMTP_PORT', '587')).to_i,
      domain: smtp[:domain].presence || ENV['SMTP_DOMAIN'].presence,
      user_name: smtp[:user_name].presence || ENV['SMTP_USER_NAME'],
      password: smtp[:password].presence || ENV['SMTP_PASSWORD'],
      authentication: (smtp[:authentication].presence || ENV.fetch('SMTP_AUTHENTICATION', 'plain')).to_sym,
      enable_starttls_auto: smtp.fetch(:enable_starttls_auto, true)
    }.compact
  else
    config.action_mailer.raise_delivery_errors = false
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # DNS-rebinding / Host-header protection. FULLY opt-in via ALLOWED_HOSTS
  # (comma-separated) — leaving it unset keeps Rails' permissive default so we
  # never lock out a domain by surprise (the app is served on both apex and
  # www). Setting APP_HOST alone does NOT enable it; when the allowlist IS set,
  # APP_HOST's host is folded in automatically.
  allowed = ENV.fetch('ALLOWED_HOSTS', '').split(',').map(&:strip).reject(&:empty?)
  if allowed.any?
    allowed << _app_uri.host if _app_uri.host.present?
    allowed.uniq.each { |h| config.hosts << h }
    # The platform health-checks /up by IP/internal hostname — never block it.
    config.host_authorization = { exclude: ->(request) { request.path == '/up' } }
  end
end
