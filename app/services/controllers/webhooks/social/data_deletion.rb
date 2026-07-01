# frozen_string_literal: true

module Controllers
  module Webhooks
    module Social
      # Handles a Meta-family **Data Deletion Request Callback** (Product Settings →
      # "Data Deletion Request URL"). Meta POSTs a signed_request with the user's
      # id; we delete that user's stored data (their SocialAccounts) and MUST
      # respond with JSON `{ url:, confirmation_code: }` — a status page the user
      # can visit + a tracking code (Meta data-deletion-request-callback docs).
      #
      # Deletion is synchronous and idempotent, so the status page always reports
      # "complete". Deletion only runs when the signature verifies.
      class DataDeletion < Controllers::Base
        def initialize(provider:, signed_request:)
          @provider = provider.to_s
          @signed_request = signed_request.to_s
        end

        def call
          data = MetaSignedRequest.parse(@signed_request, MetaSignedRequest.secret_for(@provider))
          user_id = data && data['user_id']

          Operations::Social::DeleteUserData.call(providers: [@provider], external_user_id: user_id) if user_id.present?

          code = SecureRandom.hex(10)
          { url: "#{SystemConfig.app_host}/data-deletion?code=#{code}", confirmation_code: code }
        end
      end
    end
  end
end
