# frozen_string_literal: true

# Active Record Encryption keys for the `encrypts` columns (per-workspace OAuth
# tokens on SocialAccount / Setting, personal Google tokens on User).
#
# In production these MUST come from Rails encrypted credentials or a secret
# manager. For local development we fall back to fixed dev keys via ENV so the
# `encrypts` columns work out of the box. Never reuse these in production.
config = Rails.application.config.active_record.encryption

config.primary_key            = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY") { "wHAldJ4MrYx4XGOs88NEWfUrBxr3todz" }
config.deterministic_key      = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY") { "iQPazTCnQdpi9trNJru1Ce75TyW9n6SP" }
config.key_derivation_salt    = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT") { "9HicjwalX351iUPaitlOOeC16eTSUoAp" }
config.support_unencrypted_data = true
