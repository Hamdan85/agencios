# frozen_string_literal: true

module Vendors
  module InstagramLogin
    module Actions
      # Build the Instagram Login authorize URL. The user logs in with their own
      # Instagram Professional account — no Facebook Page, no Business Manager
      # (instagram-login.md §3). `enable_fb_login=0` keeps it pure Instagram.
      class AuthorizeUrl
        def self.call(...) = new(...).call

        # Permissions for the Instagram Login product (instagram-login.md §3).
        SCOPES = %w[
          instagram_business_basic
          instagram_business_content_publish
          instagram_business_manage_comments
          instagram_business_manage_insights
        ].freeze

        def initialize(workspace:, redirect_uri:, state:, client: nil)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
          @client = client || Vendors::InstagramLogin::Client.new
        end

        def call
          params = {
            client_id: @client.app_id,
            redirect_uri: @redirect_uri,
            response_type: 'code',
            scope: SCOPES.join(','),
            state: @state,
            enable_fb_login: '0',
            force_authentication: '1'
          }
          "#{@client.authorize_url_base}?#{URI.encode_www_form(params)}"
        end
      end
    end
  end
end
