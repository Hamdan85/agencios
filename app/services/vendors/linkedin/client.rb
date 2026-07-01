# frozen_string_literal: true

require 'net/http'
require 'uri'

module Vendors
  module Linkedin
    # Low-level LinkedIn API wrapper.
    #
    # Three surfaces, each with its own auth + header shape:
    #   1. OAuth   — www.linkedin.com/oauth/v2/*           (form-encoded, no version header)
    #   2. /v2/*   — api.linkedin.com/v2/userinfo          (Bearer only, no version header)
    #   3. /rest/* — api.linkedin.com/rest/*               (Bearer + LinkedIn-Version + X-Restli-Protocol-Version)
    #   4. dms-uploads — www.linkedin.com/dms-uploads/...  (signed URL, raw binary PUT, NO versioned headers)
    #
    # App-level secrets (client_id/client_secret) come from credentials; the
    # per-workspace access_token comes from the SocialAccount passed in.
    # See docs/integrations/linkedin.md.
    class Client < Vendors::Base
      OAUTH_HOST = 'https://www.linkedin.com'
      API_HOST   = 'https://api.linkedin.com'

      # LinkedIn-Version is mandatory on every /rest/* call (YYYYMM). Bump ~yearly,
      # always inside the 1-year support window. June 2026 is the current version.
      LINKEDIN_VERSION   = '202606'
      RESTLI_VERSION     = '2.0.0'

      def initialize(social_account: nil, access_token: nil)
        @social_account = social_account
        @access_token   = access_token || social_account&.user_access_token
        @client_id      = require_credential!(
          credential(:linkedin, :client_id, env: 'LINKEDIN_CLIENT_ID'), 'linkedin.client_id'
        )
        @client_secret = require_credential!(
          credential(:linkedin, :client_secret, env: 'LINKEDIN_CLIENT_SECRET'), 'linkedin.client_secret'
        )
      end

      attr_reader :client_id, :client_secret

      # --- OAuth (form-encoded) -------------------------------------------------

      # POST /oauth/v2/accessToken — used for both code exchange and refresh.
      def token_request(form)
        conn = build_connection(OAUTH_HOST, headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
        handle(conn.post('/oauth/v2/accessToken') do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = URI.encode_www_form(form)
        end)
      end

      # --- /v2/userinfo (Bearer only) ------------------------------------------

      def userinfo
        conn = build_connection(API_HOST, auth_token: token!)
        handle(conn.get('/v2/userinfo'))
      end

      # --- /rest/* (versioned) --------------------------------------------------

      def rest_get(path, params = {})
        handle(rest_connection.get(path) { |req| req.params.update(params) if params.any? })
      end

      # Returns the raw Faraday::Response so callers can read response headers
      # (e.g. x-restli-id after creating a post).
      def rest_post_raw(path, body, extra_headers: {})
        rest_connection.post(path) do |req|
          extra_headers.each { |k, v| req.headers[k] = v }
          req.body = body
        end
      end

      def rest_post(path, body, extra_headers: {})
        handle(rest_post_raw(path, body, extra_headers: extra_headers))
      end

      def rest_delete(path, extra_headers: {})
        handle(rest_connection.delete(path) do |req|
          req.headers['X-RestLi-Method'] = 'DELETE'
          extra_headers.each { |k, v| req.headers[k] = v }
        end)
      end

      # --- signed dms-uploads (raw binary, NO versioned headers) ----------------

      # PUT raw bytes to a LinkedIn-signed upload URL. Returns the ETag header
      # (needed in upload order for multipart video finalize).
      def upload_binary(upload_url, bytes, content_type:)
        uri = URI.parse(upload_url)
        http = net_http_for(uri)
        request = Net::HTTP::Put.new(uri)
        request['Content-Type'] = content_type
        request['Authorization'] = "Bearer #{token!}"
        request.body = bytes
        response = http.request(request)
        unless response.code.to_i.between?(200, 299)
          raise Vendors::Base::Error.new('LinkedIn upload failed', status: response.code.to_i, body: response.body)
        end

        response['etag']
      end

      # Centralized Rest.li 2.0 URN encoding for query strings.
      def self.encode_urn(urn)
        URI.encode_www_form_component(urn)
      end

      private

      def token!
        require_credential!(@access_token, 'linkedin access_token (SocialAccount#user_access_token)')
      end

      # Every /rest/* request carries the four required headers.
      def rest_connection
        build_connection(
          API_HOST,
          headers: {
            'LinkedIn-Version' => LINKEDIN_VERSION,
            'X-Restli-Protocol-Version' => RESTLI_VERSION,
            'Content-Type' => 'application/json'
          },
          auth_token: token!
        )
      end

      def net_http_for(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 10
        http.read_timeout = 60
        http
      end
    end
  end
end
