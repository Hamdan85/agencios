# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — build the Facebook Login OAuth authorize URL
      # for connecting Instagram + Facebook in a single pass (instagram.md §4 /
      # facebook.md §4). One Meta app, one OAuth, both networks' scopes.
      class AuthorizeUrl
        def self.call(...) = new(...).call

        # Combined IG + FB scopes (instagram.md §3 + facebook.md §3), deduped.
        SCOPES = %w[
          instagram_basic
          instagram_content_publish
          instagram_manage_insights
          pages_show_list
          pages_read_engagement
          pages_manage_posts
          pages_read_user_content
          read_insights
          business_management
          public_profile
        ].freeze

        def initialize(workspace:, redirect_uri:, state:, client: nil)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
          @client = client || Vendors::Meta::Client.new
        end

        def call
          params = {
            client_id: @client.app_id,
            redirect_uri: @redirect_uri,
            state: @state,
            scope: SCOPES.join(","),
            response_type: "code"
          }
          "#{@client.dialog_url}?#{URI.encode_www_form(params)}"
        end
      end
    end
  end
end
