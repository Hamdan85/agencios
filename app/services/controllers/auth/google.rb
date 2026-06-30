# frozen_string_literal: true

module Controllers
  module Auth
    # Shared constants/helpers for the "Sign in / Sign up with Google" flow
    # (Start builds the consent URL, Callback completes it). Distinct from the
    # social-account connect flow in Controllers::Auth::Omniauth.
    module Google
      STATE_PURPOSE     = "agencios:google_auth"
      STATE_TTL         = 10.minutes
      DEFAULT_RETURN_TO = "/painel"

      # The single redirect URI registered on the Google OAuth client for sign-in.
      def self.redirect_uri = "#{SystemConfig.app_host}/auth/google/callback"

      # Only allow same-origin relative paths back into the SPA (open-redirect guard).
      def self.safe_return_to(path)
        path = path.to_s
        path.start_with?("/") && !path.start_with?("//") ? path : DEFAULT_RETURN_TO
      end
    end
  end
end
