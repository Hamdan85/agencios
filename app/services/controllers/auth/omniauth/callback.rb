# frozen_string_literal: true

module Controllers
  module Auth
    module Omniauth
      # Verifies the signed OAuth state (which carries the connecting workspace),
      # exchanges the code via the network vendor, and persists the SocialAccount(s).
      # Returns the network slug on success; the controller maps it to a redirect.
      class Callback < Controllers::Base
        def initialize(provider:, code:, state:)
          @provider = provider.to_s
          @code = code
          @state = state
        end

        def call
          data = verify_state(@state)
          raise Operations::Errors::Invalid, "state" unless data

          target = Workspace.find(data["workspace_id"])
          vendor = Publishers::SocialPublisher.vendor_for_slug(@provider)
          attrs = vendor::Actions::ConnectAccount.call(
            code: @code, workspace: target, redirect_uri: redirect_uri
          )

          Array(attrs).each { |a| Operations::Social::ConnectAccount.call(workspace: target, attrs: a) }
          @provider
        end

        private

        def redirect_uri
          "#{SystemConfig.app_host}/auth/#{@provider}/callback"
        end

        def verify_state(token)
          Rails.application.message_verifier("agencios:social_connect").verify(token.to_s)
        rescue StandardError
          nil
        end
      end
    end
  end
end
