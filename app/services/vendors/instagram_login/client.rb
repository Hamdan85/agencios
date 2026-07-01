# frozen_string_literal: true

module Vendors
  # "Instagram API with Instagram Login" — the Page-less, Business-Manager-less
  # path. The client logs in with their own Instagram Professional account
  # (Business or Creator); no Facebook Page link required. This is the easy,
  # non-technical onboarding path (docs/integrations/instagram-login.md).
  #
  # Distinct from Vendors::Meta (Facebook Login): different hosts, a different
  # app id/secret (the "Instagram app" inside the same Meta app), and IG-user
  # tokens used directly against graph.instagram.com for publishing/insights.
  module InstagramLogin
    class Client < Vendors::Base
      DEFAULT_GRAPH_VERSION = 'v23.0'

      AUTHORIZE_HOST = 'https://www.instagram.com' # OAuth authorize dialog
      OAUTH_HOST     = 'https://api.instagram.com'      # code → short-lived token
      GRAPH_HOST     = 'https://graph.instagram.com'    # long-lived token, profile, publish

      attr_reader :access_token, :graph_version

      # Pass a SocialAccount (publishing/insights use its user_access_token) or an
      # explicit access_token (OAuth steps, before an account exists).
      def initialize(social_account = nil, access_token: nil, graph_version: nil)
        @social_account = social_account
        @access_token   = access_token || social_account&.user_access_token
        @graph_version  = graph_version || credential(:meta, :graph_version) || DEFAULT_GRAPH_VERSION
      end

      # The "Instagram app" id/secret from the Meta app's "Instagram API with
      # Instagram Login" product — NOT the Facebook app id/secret.
      def app_id
        require_credential!(
          credential(:meta, :instagram_app_id, env: 'INSTAGRAM_APP_ID'), 'meta.instagram_app_id'
        )
      end

      def app_secret
        require_credential!(
          credential(:meta, :instagram_app_secret, env: 'INSTAGRAM_APP_SECRET'), 'meta.instagram_app_secret'
        )
      end

      def authorize_url_base = "#{AUTHORIZE_HOST}/oauth/authorize"

      # GET on graph.instagram.com (long-lived exchange, profile, insights).
      def graph_get(path, params: {}, token: access_token)
        params = { access_token: token }.merge(params.compact) if token && !params.key?(:access_token)
        handle(build_connection("#{GRAPH_HOST}/").get(join(path), params))
      end

      # POST form on api.instagram.com (authorization_code → short-lived token).
      def oauth_post(path, params: {})
        conn = Faraday.new(url: "#{OAUTH_HOST}/") do |f|
          f.response :json, content_type: /\bjson/
          f.options.timeout = 30
          f.adapter Faraday.default_adapter
        end
        handle(conn.post(join(path)) do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = URI.encode_www_form(params)
        end)
      end

      private

      def join(path) = path.to_s.start_with?('/') ? path.to_s[1..] : path.to_s
    end
  end
end
