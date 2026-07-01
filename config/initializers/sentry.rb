# frozen_string_literal: true

# Error monitoring. The DSN lives in encrypted credentials (per-environment),
# never in source or `.env`. Sentry stays disabled when no DSN is configured
# (e.g. test, or a dev machine without the key).
sentry_dsn = Rails.application.credentials.dig(:sentry, :dsn)

if sentry_dsn.present?
  Sentry.init do |config|
    config.dsn = sentry_dsn
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    config.enabled_environments = %w[production staging]

    # Add data like request headers and IP for users, see
    # https://docs.sentry.io/platforms/ruby/data-management/data-collected/
    config.send_default_pii = true
  end
end
