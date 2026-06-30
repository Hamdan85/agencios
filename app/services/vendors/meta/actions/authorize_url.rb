# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — build the Facebook Login OAuth authorize URL for
      # connecting Facebook Pages (facebook.md §4). Instagram is connected
      # separately via Instagram Login (no Facebook Page), so NO instagram_*
      # scopes here. When meta.fb_login_config_id is set, the dialog sends that
      # config_id INSTEAD of this scope list (Facebook Login for Business).
      class AuthorizeUrl
        def self.call(...) = new(...).call

        # Facebook Page scopes only. These must match the permissions selected in
        # the Facebook Login for Business configuration (and the app must have the
        # "Manage everything on your Page" use case, which grants pages_manage_posts
        # / pages_read_user_content / read_insights). Used only on the scope
        # fallback when no config_id is configured.
        SCOPES = %w[
          pages_show_list
          pages_read_engagement
          pages_manage_posts
          pages_read_user_content
          read_insights
          business_management
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
            response_type: "code"
          }
          # Facebook Login for Business: a dashboard-created configuration
          # (config_id) replaces scope. Fall back to the classic scope-based
          # dialog when no configuration is set (meta.md §4).
          config_id = @client.fb_login_config_id
          if config_id.present?
            params[:config_id] = config_id
          else
            params[:scope] = SCOPES.join(",")
          end
          "#{@client.dialog_url}?#{URI.encode_www_form(params)}"
        end
      end
    end
  end
end
