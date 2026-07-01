# frozen_string_literal: true

module Vendors
  module InstagramLogin
    module Actions
      # Resolve the connected Instagram account's identity (instagram-login.md §4).
      # `user_id` is the IG-scoped id used as the publish/insights target on
      # graph.instagram.com. Returns
      # { "user_id" => ..., "username" => ..., "account_type" => ..., "profile_picture_url" => ... }.
      class GetProfile
        def self.call(...) = new(...).call

        FIELDS = 'user_id,username,account_type,profile_picture_url'

        def initialize(access_token:, client: nil)
          @access_token = access_token
          @client = client || Vendors::InstagramLogin::Client.new
        end

        def call
          @client.graph_get('/me', params: { fields: FIELDS }, token: @access_token)
        end
      end
    end
  end
end
