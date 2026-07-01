# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Resolve the connected Threads account identity (threads.md §4). `id` is the
      # Threads user id used as the publish/insights target. Returns
      # { "id" => ..., "username" => ..., "threads_profile_picture_url" => ... }.
      class GetProfile
        def self.call(...) = new(...).call

        FIELDS = 'id,username,threads_profile_picture_url'

        def initialize(access_token:, client: nil)
          @access_token = access_token
          @client = client || Vendors::Threads::Client.new
        end

        def call
          @client.get('/me', params: { fields: FIELDS }, token: @access_token)
        end
      end
    end
  end
end
