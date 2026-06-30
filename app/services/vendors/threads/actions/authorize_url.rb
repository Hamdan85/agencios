# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Build the Threads authorize URL. The user logs in with their own Threads
      # account — no Facebook Page (threads.md §3).
      class AuthorizeUrl
        def self.call(...) = new(...).call

        SCOPES = %w[
          threads_basic
          threads_content_publish
          threads_manage_insights
          threads_manage_replies
        ].freeze

        def initialize(workspace:, redirect_uri:, state:, client: nil)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
          @client = client || Vendors::Threads::Client.new
        end

        def call
          params = {
            client_id: @client.app_id,
            redirect_uri: @redirect_uri,
            response_type: "code",
            scope: SCOPES.join(","),
            state: @state
          }
          "#{@client.authorize_url_base}?#{URI.encode_www_form(params)}"
        end
      end
    end
  end
end
