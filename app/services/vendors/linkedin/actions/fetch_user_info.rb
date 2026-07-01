# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET https://api.linkedin.com/v2/userinfo — resolves the member identity.
      # The `sub` field is the bare member id; build urn:li:person:{sub}.
      # NOTE: /v2/userinfo carries no LinkedIn-Version header (Bearer only).
      # See docs/integrations/linkedin.md §5.
      class FetchUserInfo
        def self.call(...) = new(...).call

        def initialize(access_token: nil, social_account: nil)
          @access_token = access_token
          @social_account = social_account
        end

        # Returns { member_id:, member_urn:, member_name:, member_email: }.
        def call
          body = Vendors::Linkedin::Client.new(
            access_token: @access_token, social_account: @social_account
          ).userinfo

          sub = body['sub']
          {
            member_id: sub,
            member_urn: "urn:li:person:#{sub}",
            member_name: body['name'],
            member_email: body['email']
          }
        end
      end
    end
  end
end
