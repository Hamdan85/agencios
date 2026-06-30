# frozen_string_literal: true

module Controllers
  module Auth
    module Calendar
      # Verifies the signed state (carrying workspace_id), exchanges the
      # authorization code for tokens, and persists them on the workspace Setting.
      # Called by Auth::CalendarController#callback — this is a browser-facing
      # request, so Current.workspace is not set; workspace is resolved from state.
      class Callback
        def self.call(...) = new(...).call

        def initialize(code:, state:)
          @code  = code
          @state = state
        end

        def call
          data      = verify_state!
          raise Operations::Errors::Invalid, "code missing" if @code.blank?

          workspace = Workspace.find(data["workspace_id"])
          token     = Vendors::Google::Actions::ExchangeCode.call(
            code: @code, redirect_uri: Calendar.redirect_uri
          )

          setting = workspace.setting || Setting.create!(workspace: workspace)
          setting.update!(
            google_access_token:          token["access_token"],
            google_refresh_token:         token["refresh_token"].presence || setting.google_refresh_token,
            google_calendar_connected_at: Time.current
          )
        end

        private

        def verify_state!
          Rails.application.message_verifier(Calendar::STATE_PURPOSE).verify(@state.to_s)
        rescue ActiveSupport::MessageVerifier::InvalidSignature,
               ActiveSupport::MessageEncryptor::InvalidMessage
          raise Operations::Errors::Invalid, "State inválido ou expirado."
        end
      end
    end
  end
end
