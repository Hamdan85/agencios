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
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.enabled_environments = %w[production staging]
    config.send_default_pii   = false
    config.enable_logs        = true
    config.enabled_patches    = [ :logger ]
    config.traces_sample_rate   = 0.2
    config.profiles_sample_rate = 0.1
    config.before_send = lambda do |event, _hint|
      event.user = { id: event.user&.[](:id) }.compact
      event
    end
  end
end
