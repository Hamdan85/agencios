# frozen_string_literal: true

module Vendors
  # Threads API (Meta) — structurally the same as Instagram Login: the user logs
  # in with their own Threads account (no Facebook Page), and a Threads user token
  # is used directly against graph.threads.net for publishing/insights. The
  # Threads app id/secret come from the Meta app's "Access the Threads API" use
  # case (docs/integrations/threads.md).
  module Threads
    class Client < Vendors::Base
      DEFAULT_GRAPH_VERSION = "v1.0"

      AUTHORIZE_HOST = "https://threads.net"        # OAuth authorize dialog
      GRAPH_HOST     = "https://graph.threads.net"  # token exchange, profile, publish

      attr_reader :access_token, :graph_version

      # Pass a SocialAccount (publishing/insights use its user_access_token) or an
      # explicit access_token (OAuth steps, before an account exists).
      def initialize(social_account = nil, access_token: nil, graph_version: nil)
        @social_account = social_account
        @access_token   = access_token || social_account&.user_access_token
        @graph_version  = graph_version || credential(:meta, :threads_graph_version) || DEFAULT_GRAPH_VERSION
      end

      def app_id
        require_credential!(
          credential(:meta, :threads_app_id, env: "THREADS_APP_ID"), "meta.threads_app_id"
        )
      end

      def app_secret
        require_credential!(
          credential(:meta, :threads_app_secret, env: "THREADS_APP_SECRET"), "meta.threads_app_secret"
        )
      end

      def authorize_url_base = "#{AUTHORIZE_HOST}/oauth/authorize"

      # Versioned base for graph data calls (profile, publish, insights).
      def graph_base = "#{GRAPH_HOST}/#{graph_version}"

      # --- Versioned graph data calls (profile / publish / insights) ----------

      def get(path, params: {}, token: access_token)
        params = { access_token: token }.merge(params.compact) if token && !params.key?(:access_token)
        handle(build_connection("#{graph_base}/").get(join(path), params))
      end

      def post(path, params: {}, token: access_token)
        params = { access_token: token }.merge(params.compact) if token && !params.key?(:access_token)
        handle(form_connection("#{graph_base}/").post(join(path)) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(params)
        end)
      end

      # --- Unversioned OAuth endpoints (token exchange / refresh) --------------

      def oauth_post(path, params: {})
        handle(form_connection("#{GRAPH_HOST}/").post(join(path)) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(params)
        end)
      end

      def oauth_get(path, params: {})
        handle(build_connection("#{GRAPH_HOST}/").get(join(path), params.compact))
      end

      private

      def form_connection(base) = raw_connection(base)

      def join(path) = path.to_s.start_with?("/") ? path.to_s[1..] : path.to_s
    end
  end
end
