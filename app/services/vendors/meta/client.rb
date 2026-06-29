# frozen_string_literal: true

module Vendors
  module Meta
    # Low-level Meta Graph API wrapper, shared by Instagram + Facebook (one Meta
    # app, one OAuth). Holds the access token + the Graph base URL and exposes
    # thin get/post/upload helpers built on Vendors::Base's Faraday plumbing.
    #
    # All publishing/insights calls use the Page access token (Facebook Login
    # flow). App id/secret come from Rails credentials (ENV fallback for dev).
    #
    # See docs/integrations/instagram.md and docs/integrations/facebook.md.
    class Client < Vendors::Base
      # Pin the Graph API version (instagram.md/facebook.md §0). Overridable via
      # the meta.graph_version credential without a code change.
      DEFAULT_GRAPH_VERSION = "v25.0"

      GRAPH_HOST  = "https://graph.facebook.com"
      # Host the user is redirected to for the OAuth authorize dialog.
      DIALOG_HOST = "https://www.facebook.com"
      # Resumable upload host for IG Reels raw bytes + FB Reels binary.
      RUPLOAD_HOST = "https://rupload.facebook.com"

      attr_reader :access_token, :graph_version

      # Pass a SocialAccount (publishing/insights use its page_access_token) or an
      # explicit access_token (OAuth steps, before an account exists).
      def initialize(social_account = nil, access_token: nil, graph_version: nil)
        @social_account = social_account
        @access_token   = access_token || social_account&.page_access_token
        @graph_version  = graph_version || credential(:meta, :graph_version) || DEFAULT_GRAPH_VERSION
      end

      def app_id
        require_credential!(credential(:meta, :app_id, env: "META_APP_ID"), "meta.app_id")
      end

      def app_secret
        require_credential!(credential(:meta, :app_secret, env: "META_APP_SECRET"), "meta.app_secret")
      end

      def webhook_verify_token
        credential(:meta, :webhook_verify_token, env: "META_WEBHOOK_VERIFY_TOKEN")
      end

      # Base for all versioned Graph calls, e.g. https://graph.facebook.com/v25.0
      def graph_base
        "#{GRAPH_HOST}/#{graph_version}"
      end

      def dialog_url
        "#{DIALOG_HOST}/#{graph_version}/dialog/oauth"
      end

      # GET {path} on the Graph API. `params` are query params; the access token
      # is appended unless explicitly provided in `params`.
      def get(path, params: {}, token: access_token)
        params = { access_token: token }.merge(params.compact) if token && !params.key?(:access_token)
        handle(connection.get(join(path), params))
      end

      # POST {path} on the Graph API. Meta write endpoints take form params
      # (sent as the request body), so encode as www-form-urlencoded.
      def post(path, params: {}, token: access_token)
        params = { access_token: token }.merge(params.compact) if token && !params.key?(:access_token)
        handle(form_connection.post(join(path)) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(params)
        end)
      end

      # Raw-byte upload to the rupload host (IG Reels resumable, FB Reels binary).
      # Headers carry the OAuth token + offset/file_size per the docs.
      def rupload(path, body:, headers:, token: access_token)
        handle(raw_connection(RUPLOAD_HOST).post(path) do |req|
          req.headers["Authorization"] = "OAuth #{token}"
          headers.each { |k, v| req.headers[k.to_s] = v.to_s }
          req.body = body
        end)
      end

      private

      # JSON-decoding connection for GETs (Graph returns JSON). Inherited
      # build_connection adds JSON encode/decode + retry.
      def connection
        @connection ||= build_connection(graph_base)
      end

      # Form-encoded write connection: JSON responses are still decoded, but we
      # set the body + Content-Type per request (raw connection, no JSON request
      # middleware that would override the form Content-Type).
      def form_connection
        @form_connection ||= raw_connection(graph_base)
      end

      # A connection that decodes JSON responses + retries, but does NOT JSON-
      # encode the request body (we control the body/headers per call).
      def raw_connection(base_url)
        Faraday.new(url: base_url) do |f|
          f.response :json, content_type: /\bjson/
          f.request :retry,
                    max: 2, interval: 0.4, backoff_factor: 2,
                    retry_statuses: RETRY_STATUSES,
                    methods: %i[get post put delete patch]
          f.options.timeout = 60
          f.options.open_timeout = 10
          f.adapter Faraday.default_adapter
        end
      end

      def join(path)
        path.to_s.start_with?("/") ? path.to_s[1..] : path.to_s
      end
    end
  end
end
