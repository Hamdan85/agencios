# frozen_string_literal: true

module Vendors
  module Google
    module Actions
      # Builds the Google consent URL for Calendar access (workspace integration).
      # Requests calendar.events scope with access_type=offline + prompt=consent
      # so a refresh token is always returned — needed for background syncing
      # (SyncToCalendar) that runs without a live user session.
      class CalendarAuthorizeUrl < Vendors::Base
        SCOPE = "https://www.googleapis.com/auth/calendar.events"
        AUTH  = "https://accounts.google.com"

        def self.call(...) = new(...).call

        def initialize(redirect_uri:, state:)
          @redirect_uri = redirect_uri
          @state = state
        end

        def call
          params = {
            client_id:              require_credential!(credential(:google, :client_id, env: "GOOGLE_CLIENT_ID"), "google.client_id"),
            redirect_uri:           @redirect_uri,
            response_type:          "code",
            scope:                  SCOPE,
            access_type:            "offline",
            prompt:                 "consent",
            include_granted_scopes: "true",
            state:                  @state
          }
          "#{AUTH}/o/oauth2/v2/auth?#{params.to_query}"
        end
      end
    end
  end
end
