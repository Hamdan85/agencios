# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # GET /2/users/me — resolve the authenticated user's id + handle to store on
      # the SocialAccount. Needs `users.read`.
      # See docs/integrations/x-twitter.md §3 (scopes) / §5 (store handle/id).
      class FetchUser
        def self.call(...) = new(...).call

        def initialize(access_token: nil, social_account: nil)
          @access_token = access_token
          @social_account = social_account
        end

        # Returns { id:, username:, name: }.
        def call
          body = Vendors::X::Client.new(
            access_token: @access_token, social_account: @social_account
          ).get_json('/2/users/me')
          data = body['data'] || {}
          { id: data['id'], username: data['username'], name: data['name'] }
        end
      end
    end
  end
end
