# frozen_string_literal: true

module Controllers
  module Sessions
    # Authenticates an email/password pair, returning the User or nil. The cookie
    # session lifecycle (start_new_session_for) is an HTTP concern handled by the
    # controller; this service owns only the credential check.
    class Create < Base
      def initialize(email:, password:)
        @email = email
        @password = password
      end

      def call
        user = User.find_by(email: @email.to_s.strip.downcase)
        return unless user&.authenticate(@password.to_s)

        # PostHog owns `login` server-side; the SPA keeps it for GTM only, so the
        # event is never double-counted. Same distinct_id → one person.
        Vendors::Posthog::Actions::Capture.call(user: user, event: 'login', properties: { method: 'password' })
        user
      end
    end
  end
end
