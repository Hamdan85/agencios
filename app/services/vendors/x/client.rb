# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'securerandom'
require 'digest'
require 'base64'

module Vendors
  module X
    # Low-level X (Twitter) API v2 wrapper.
    #
    # Surfaces:
    #   - OAuth 2.0 PKCE token endpoint  POST https://api.x.com/2/oauth2/token
    #     (confidential client -> HTTP Basic client_id:client_secret)
    #   - v2 JSON API                    https://api.x.com/2/*  (Bearer user token)
    #   - chunked media upload           https://api.x.com/2/media/upload
    #     (INIT/FINALIZE form-encoded, APPEND multipart, STATUS query)
    #
    # App-level client_id/client_secret come from credentials; the per-account
    # user access token comes from the SocialAccount passed in.
    # See docs/integrations/x-twitter.md.
    class Client < Vendors::Base
      AUTHORIZE_URL = 'https://x.com/i/oauth2/authorize'
      API_HOST      = 'https://api.x.com'

      def initialize(social_account: nil, access_token: nil)
        @social_account = social_account
        @access_token   = access_token || social_account&.user_access_token
        @client_id      = require_credential!(
          credential(:x, :client_id, env: 'X_CLIENT_ID'), 'x.client_id'
        )
        @client_secret = require_credential!(
          credential(:x, :client_secret, env: 'X_CLIENT_SECRET'), 'x.client_secret'
        )
      end

      attr_reader :client_id, :client_secret

      # --- OAuth token endpoint (form-encoded, Basic auth) ---------------------

      # POST /2/oauth2/token — code exchange or refresh. Confidential client sends
      # HTTP Basic base64(client_id:client_secret).
      def token_request(form)
        conn = build_connection(API_HOST, headers: token_headers)
        handle(conn.post('/2/oauth2/token') do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.headers['Authorization'] = basic_auth_header
          req.body = URI.encode_www_form(form)
        end)
      end

      # --- v2 JSON API (Bearer user token) -------------------------------------

      def post_json(path, body)
        conn = build_connection(API_HOST, auth_token: token!)
        handle(conn.post(path) { |req| req.body = body })
      end

      def get_json(path, params = {})
        conn = build_connection(API_HOST, auth_token: token!)
        handle(conn.get(path) { |req| req.params.update(params) if params.any? })
      end

      # --- chunked media upload (api.x.com/2/media/upload) ---------------------

      # INIT/FINALIZE/STATUS are form-encoded; APPEND is multipart with a binary
      # `media` part. These do not go through the JSON Faraday stack — we use
      # Net::HTTP so we control the multipart body and form encoding precisely.
      def media_command(form)
        uri = URI.parse("#{API_HOST}/2/media/upload")
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{token!}"
        request.set_form_data(form)
        run_media_request(uri, request)
      end

      # APPEND a binary chunk via multipart/form-data.
      def media_append(media_id:, segment_index:, chunk:)
        uri = URI.parse("#{API_HOST}/2/media/upload")
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{token!}"
        request.set_form(
          [
            %w[command APPEND],
            ['media_id', media_id.to_s],
            ['segment_index', segment_index.to_s],
            ['media', chunk, { filename: 'blob', content_type: 'application/octet-stream' }]
          ],
          'multipart/form-data'
        )
        run_media_request(uri, request)
      end

      def media_status(media_id)
        uri = URI.parse("#{API_HOST}/2/media/upload")
        uri.query = URI.encode_www_form(command: 'STATUS', media_id: media_id)
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{token!}"
        run_media_request(uri, request)
      end

      private

      def token!
        require_credential!(@access_token, 'x access_token (SocialAccount#user_access_token)')
      end

      def token_headers
        { 'Content-Type' => 'application/x-www-form-urlencoded' }
      end

      def basic_auth_header
        "Basic #{Base64.strict_encode64("#{@client_id}:#{@client_secret}")}"
      end

      # Net::HTTP request runner shared by the media-upload commands; maps the
      # status code onto the house error classes and parses the JSON body.
      def run_media_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 60
        response = http.request(request)
        body = parse_json(response.body)
        return body if response.code.to_i.between?(200, 299)

        klass =
          case response.code.to_i
          when 401, 403 then Vendors::Base::AuthenticationError
          when 429      then Vendors::Base::RateLimitError
          when 500..599 then Vendors::Base::ServerError
          else Vendors::Base::Error
          end
        raise klass.new('X media upload failed', status: response.code.to_i, body: body)
      end

      def parse_json(raw)
        return {} if raw.to_s.strip.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        { 'raw' => raw }
      end
    end
  end
end
