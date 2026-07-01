# frozen_string_literal: true

module Controllers
  module Webhooks
    module Social
      # Shared parsing for Meta-family `signed_request` callbacks (Deauthorize +
      # Data Deletion). Format: "<base64url sig>.<base64url payload>", signed with
      # the product's OWN app secret (facebook → app_secret, instagram →
      # instagram_app_secret, threads → threads_app_secret).
      module MetaSignedRequest
        module_function

        SECRET_KEYS = {
          'facebook' => [:app_secret, 'META_APP_SECRET'],
          'instagram' => [:instagram_app_secret, 'INSTAGRAM_APP_SECRET'],
          'threads' => [:threads_app_secret, 'THREADS_APP_SECRET']
        }.freeze

        def secret_for(provider)
          key, env = SECRET_KEYS[provider.to_s]
          return nil unless key

          Rails.application.credentials.dig(:meta, key) || ENV[env]
        end

        # Verify "<sig>.<payload>" and return the payload Hash, or nil on a bad
        # signature / malformed input.
        def parse(signed_request, secret)
          return nil if secret.blank?

          encoded_sig, payload = signed_request.to_s.split('.', 2)
          return nil if encoded_sig.blank? || payload.blank?

          expected = OpenSSL::HMAC.digest('SHA256', secret.to_s, payload)
          provided = base64_url_decode(encoded_sig)
          return nil unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)

          JSON.parse(base64_url_decode(payload))
        rescue StandardError
          nil
        end

        def base64_url_decode(str)
          padded = str.to_s.tr('-_', '+/')
          padded += '=' * ((4 - (padded.length % 4)) % 4)
          Base64.decode64(padded)
        end
      end
    end
  end
end
