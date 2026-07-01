# frozen_string_literal: true

# Error monitoring. The Sentry DSN is a PUBLIC ingestion key (designed to be
# embeddable — it is NOT a secret), so read it from ENV first: it is reliably
# available at boot and immune to the credentials-decryption fragility that can
# leave Sentry uninitialized in production (Sentry.initialized? == false).
# Fall back to encrypted credentials for local/dev convenience. Sentry stays
# disabled when no DSN is configured (e.g. test, or a dev machine without a key).
sentry_dsn = ENV['SENTRY_DSN'].presence || Rails.application.credentials.dig(:sentry, :dsn)

if sentry_dsn.present?
  Sentry.init do |config|
    config.dsn = sentry_dsn
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    config.enabled_environments = %w[production staging]

    # Add data like request headers and IP for users, see
    # https://docs.sentry.io/platforms/ruby/data-management/data-collected/
    config.send_default_pii = true

    # Flip on with SENTRY_DEBUG=true to log the HTTP send + Sentry's response —
    # lets you diagnose egress/DSN issues from a prod console without a re-init.
    config.debug = ENV['SENTRY_DEBUG'] == 'true'
  end
end
