# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # OAuth step 2 — exchange the authorization code for a SHORT-LIVED Threads
      # user token (threads.md §4). POST form to graph.threads.net/oauth/access_token.
      # Returns { "access_token" => ..., "user_id" => ... }.
      class ExchangeCodeForToken
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:, client: nil)
          @code = code
          @redirect_uri = redirect_uri
          @client = client || Vendors::Threads::Client.new
        end

        def call
          @client.oauth_post(
            '/oauth/access_token',
            params: {
              client_id: @client.app_id,
              client_secret: @client.app_secret,
              grant_type: 'authorization_code',
              redirect_uri: @redirect_uri,
              code: @code
            }
          )
        end
      end
    end
  end
end
