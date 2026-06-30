# frozen_string_literal: true

module Controllers
  module Webhooks
    module Social
      # Handles a Meta-family **Deauthorize Callback** (App/Product Settings →
      # "Deauthorize Callback URL"). When a user removes our app, Meta POSTs a
      # signed_request carrying the app-scoped `user_id`; we verify it and revoke
      # that user's accounts for the provider.
      class Deauthorize < Controllers::Base
        def initialize(provider:, signed_request:)
          @provider = provider.to_s
          @signed_request = signed_request.to_s
        end

        def call
          data = MetaSignedRequest.parse(@signed_request, MetaSignedRequest.secret_for(@provider))
          user_id = data && data["user_id"]
          return 0 if user_id.blank?

          Operations::Social::Deauthorize.call(providers: [@provider], external_user_id: user_id)
        end
      end
    end
  end
end
