# frozen_string_literal: true

module Vendors
  module TikTok
    # Low-level TikTok API wrapper (Content Posting API + Display API + Login Kit
    # OAuth). Raw HTTP only — no domain logic, no DB writes. App-level secrets
    # (client_key / client_secret) come from credentials with ENV fallback;
    # per-account access tokens are passed in. See docs/integrations/tiktok.md.
    #
    # Two hosts:
    #   API   = https://open.tiktokapis.com  (token, content posting, display)
    #   OAUTH = https://www.tiktok.com        (browser authorize endpoint only)
    #
    # TikTok wraps every response in { data: {...}, error: { code:, message:, log_id: } }
    # and signals success with error.code == "ok" (HTTP 200 even on logical errors),
    # so #handle alone is not enough — we also inspect the envelope.
    class Client < Vendors::Base
      API   = 'https://open.tiktokapis.com'
      OAUTH = 'https://www.tiktok.com'

      def initialize(access_token: nil)
        @access_token = access_token
      end

      # --- Login Kit / OAuth (§4) ----------------------------------------------

      # Authorize URL the user's browser is redirected to (§4.1). Built here so the
      # client owns the host + param shape; the Action supplies scope/redirect/state.
      def authorize_url(scope:, redirect_uri:, state:, code_challenge: nil)
        params = {
          client_key: client_key,
          scope: scope,
          response_type: 'code',
          redirect_uri: redirect_uri,
          state: state
        }
        if code_challenge
          params[:code_challenge] = code_challenge
          params[:code_challenge_method] = 'S256'
        end
        "#{OAUTH}/v2/auth/authorize/?#{params.to_query}"
      end

      # POST /v2/oauth/token/ grant_type=authorization_code (§4.2)
      def exchange_code(code:, redirect_uri:, code_verifier: nil)
        form_post('/v2/oauth/token/', {
          client_key: client_key,
          client_secret: client_secret,
          code: code,
          grant_type: 'authorization_code',
          redirect_uri: redirect_uri,
          code_verifier: code_verifier
        }.compact)
      end

      # POST /v2/oauth/token/ grant_type=refresh_token (§4.3) — may rotate refresh_token.
      def refresh(refresh_token:)
        form_post('/v2/oauth/token/', {
                    client_key: client_key,
                    client_secret: client_secret,
                    grant_type: 'refresh_token',
                    refresh_token: refresh_token
                  })
      end

      # POST /v2/oauth/revoke/ (§4.4)
      def revoke(token:)
        form_post('/v2/oauth/revoke/', {
                    client_key: client_key,
                    client_secret: client_secret,
                    token: token
                  })
      end

      # --- Content Posting API (§6) --------------------------------------------

      # Mandatory before every post (§6.0). Returns creator_info data.
      def query_creator_info
        json_post('/v2/post/publish/creator_info/query/', {})
      end

      # Direct Post video init (§6.1). source_info selects FILE_UPLOAD or PULL_FROM_URL.
      def init_video(post_info:, source_info:)
        json_post('/v2/post/publish/video/init/', { post_info: post_info, source_info: source_info })
      end

      # Photo / carousel init (§6.4) — unified content/init endpoint.
      def init_content(payload)
        json_post('/v2/post/publish/content/init/', payload)
      end

      # Poll publish status (§6.3).
      def fetch_status(publish_id:)
        json_post('/v2/post/publish/status/fetch/', { publish_id: publish_id })
      end

      # PUT a single chunk to the upload_url returned by init_video (FILE_UPLOAD, §6.2).
      # content_range is 0-indexed inclusive, e.g. "bytes 0-30567099/30567100".
      # Returns the raw Faraday response (201 for whole-file, 206 for partial).
      def upload_chunk(upload_url:, bytes:, content_range:, mime: 'video/mp4')
        conn = Faraday.new do |f|
          f.request :retry,
                    max: 2, interval: 0.4, backoff_factor: 2,
                    retry_statuses: Vendors::Base::RETRY_STATUSES,
                    methods: %i[put]
          f.adapter Faraday.default_adapter
        end
        conn.put(upload_url) do |req|
          req.headers['Content-Type']   = mime
          req.headers['Content-Length'] = bytes.bytesize.to_s
          req.headers['Content-Range']  = content_range
          req.body = bytes
        end
      end

      # --- Display API (§7) ----------------------------------------------------

      # GET /v2/user/info/?fields=... (§7.1) — account stats / profile.
      def user_info(fields:)
        json_get('/v2/user/info/', fields: fields)
      end

      # POST /v2/video/list/?fields=... (§7.2) — paginated public videos + metrics.
      def video_list(fields:, max_count: 20, cursor: 0)
        json_post("/v2/video/list/?fields=#{fields}", { max_count: max_count, cursor: cursor })
      end

      # POST /v2/video/query/?fields=... (§7.2) — same fields filtered by video ids.
      def video_query(fields:, video_ids:)
        json_post("/v2/video/query/?fields=#{fields}", { filters: { video_ids: video_ids } })
      end

      # Webhook signature secret (= client_secret unless TikTok issues a separate one, §5.1).
      def webhook_secret
        credential(:tiktok, :webhook_secret, env: 'TIKTOK_WEBHOOK_SECRET') || client_secret
      end

      private

      def client_key
        require_credential!(credential(:tiktok, :client_key, env: 'TIKTOK_CLIENT_KEY'), 'tiktok.client_key')
      end

      def client_secret
        require_credential!(credential(:tiktok, :client_secret, env: 'TIKTOK_CLIENT_SECRET'), 'tiktok.client_secret')
      end

      # application/x-www-form-urlencoded POST (OAuth token/revoke). No bearer auth.
      def form_post(path, body)
        conn = Faraday.new(url: API) do |f|
          f.request :url_encoded
          f.response :json, content_type: /\bjson/
          f.request :retry,
                    max: 2, interval: 0.4, backoff_factor: 2,
                    retry_statuses: Vendors::Base::RETRY_STATUSES,
                    methods: %i[post]
          f.options.timeout = 30
          f.options.open_timeout = 10
          f.adapter Faraday.default_adapter
        end
        check_oauth(handle(conn.post(path, body)))
      end

      # JSON POST with bearer auth + TikTok envelope check.
      def json_post(path, body)
        check_envelope(handle(json_connection.post(path, body)))
      end

      # JSON GET with bearer auth + TikTok envelope check. fields go on the query string.
      def json_get(path, **query)
        check_envelope(handle(json_connection.get(path) { |req| req.params.update(query) }))
      end

      def json_connection
        build_connection(
          API,
          headers: { 'Content-Type' => 'application/json; charset=UTF-8' },
          auth_token: @access_token
        )
      end

      # TikTok returns 200 with error.code != "ok" for logical failures — map those.
      def check_envelope(body)
        return body unless body.is_a?(Hash)

        error = body['error']
        return body if error.nil? || error['code'].nil? || error['code'] == 'ok'

        raise_tiktok_error(error)
      end

      # OAuth token endpoint uses a flat { error:, error_description: } on failure.
      def check_oauth(body)
        return body unless body.is_a?(Hash) && body['error'].is_a?(String)

        raise Vendors::Base::AuthenticationError.new(
          body['error_description'] || body['error'], body: body
        )
      end

      def raise_tiktok_error(error)
        code = error['code']
        message = "#{code}: #{error['message']} (log_id=#{error['log_id']})"
        klass =
          case code
          when 'access_token_invalid', 'scope_not_authorized', 'scope_permission_missed'
            Vendors::Base::AuthenticationError
          when 'rate_limit_exceeded'
            Vendors::Base::RateLimitError
          when 'internal_error'
            Vendors::Base::ServerError
          else
            Vendors::Base::Error
          end
        raise klass.new(message, body: error)
      end
    end
  end
end
