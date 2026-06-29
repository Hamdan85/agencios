# frozen_string_literal: true

module Vendors
  module Youtube
    # Low-level YouTube wrapper: Data API v3 (videos.insert resumable, thumbnails.set,
    # channels.list), Analytics API (reports.query), and Google OAuth 2.0. Raw HTTP
    # only — no DB writes, no domain logic. OAuth app credentials (client_id /
    # client_secret) come from credentials with ENV fallback; per-account access
    # tokens are passed in. See docs/integrations/youtube.md.
    #
    # Hosts:
    #   AUTH      = https://accounts.google.com   (browser consent URL, §4.1)
    #   TOKEN     = https://oauth2.googleapis.com  (token exchange/refresh, §4.2-4.3)
    #   DATA      = https://www.googleapis.com     (Data API + resumable upload, §6-7.2)
    #   ANALYTICS = https://youtubeanalytics.googleapis.com (reports.query, §7.1)
    #   PUBSUB    = https://pubsubhubbub.appspot.com (push subscribe, §8)
    class Client < Vendors::Base
      AUTH      = "https://accounts.google.com"
      TOKEN     = "https://oauth2.googleapis.com"
      DATA      = "https://www.googleapis.com"
      ANALYTICS = "https://youtubeanalytics.googleapis.com"
      PUBSUB    = "https://pubsubhubbub.appspot.com"

      def initialize(access_token: nil)
        @access_token = access_token
      end

      # --- OAuth (§4) ----------------------------------------------------------

      # Consent URL (§4.1). access_type=offline + prompt=consent guarantee a refresh_token.
      def authorize_url(scope:, redirect_uri:, state:)
        params = {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: scope,
          access_type: "offline",
          prompt: "consent",
          include_granted_scopes: "true",
          state: state
        }
        "#{AUTH}/o/oauth2/v2/auth?#{params.to_query}"
      end

      # POST oauth2.googleapis.com/token grant_type=authorization_code (§4.2).
      def exchange_code(code:, redirect_uri:)
        token_post({
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code"
        })
      end

      # POST oauth2.googleapis.com/token grant_type=refresh_token (§4.3).
      # Returns a fresh access_token + expires_in; no new refresh_token.
      def refresh(refresh_token:)
        token_post({
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token,
          grant_type: "refresh_token"
        })
      end

      # --- Data API: channel + thumbnails (§6.6, §7.2) -------------------------

      # GET /youtube/v3/channels?part=...&mine=true (1 unit). Resolves channel id/title/stats.
      def list_channels(part: "id,snippet")
        json_get_data("/youtube/v3/channels", part: part, mine: "true")
      end

      # POST upload/youtube/v3/thumbnails/set?videoId=... (§6.6, 50 units).
      # Requires a phone-verified channel, else 403. image_bytes raw jpeg/png.
      def set_thumbnail(video_id:, image_bytes:, content_type: "image/jpeg")
        conn = upload_connection(content_type)
        handle(conn.post("/upload/youtube/v3/thumbnails/set") do |req|
          req.params["videoId"] = video_id
          req.body = image_bytes
        end)
      end

      # --- Data API: resumable video upload (§6.2-6.4) -------------------------

      # Step 1 — initiate the resumable session (§6.2). Returns the session URI from
      # the Location header. videos.insert ≈ 100 units (dropped from ~1600 on
      # 2025-12-04; default daily quota 10,000 units → ~100 uploads/day).
      def init_resumable_upload(metadata:, total_size:, content_type: "video/*", notify_subscribers: true)
        conn = build_connection(
          DATA,
          headers: {
            "Content-Type" => "application/json; charset=UTF-8",
            "X-Upload-Content-Length" => total_size.to_s,
            "X-Upload-Content-Type" => content_type
          },
          auth_token: @access_token
        )
        response = conn.post("/upload/youtube/v3/videos") do |req|
          req.params["uploadType"] = "resumable"
          req.params["part"] = "snippet,status"
          req.params["notifySubscribers"] = notify_subscribers.to_s
          req.body = metadata
        end
        raise_for_status(response)
        response.headers["location"] || response.headers["Location"]
      end

      # Step 2 — PUT the bytes to the session URI (§6.3). Whole-file by default.
      # Returns the raw response; 201 Created on the final chunk carries the video resource.
      def upload_bytes(session_uri:, bytes:, content_range: nil, content_type: "video/*")
        conn = raw_connection
        conn.put(session_uri) do |req|
          req.headers["Content-Type"] = content_type
          req.headers["Content-Length"] = bytes.bytesize.to_s
          req.headers["Content-Range"] = content_range if content_range
          req.body = bytes
        end
      end

      # Step 3 — query how much of an interrupted upload was received (§6.4).
      # PUT with Content-Range: bytes */TOTAL and empty body → 308 + Range header.
      def query_upload_status(session_uri:, total_size:)
        raw_connection.put(session_uri) do |req|
          req.headers["Content-Length"] = "0"
          req.headers["Content-Range"] = "bytes */#{total_size}"
        end
      end

      # --- Analytics API (§7.1) ------------------------------------------------

      # GET youtubeanalytics.googleapis.com/v2/reports (scope yt-analytics.readonly).
      def reports_query(params)
        conn = build_connection(ANALYTICS, auth_token: @access_token)
        handle(conn.get("/v2/reports") { |req| req.params.update(params) })
      end

      # --- PubSubHubbub push subscribe (§8) ------------------------------------

      def subscribe_push(callback_url:, topic_url:, mode: "subscribe", verify: "async")
        conn = Faraday.new(url: PUBSUB) do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
        end
        conn.post("/subscribe", {
          "hub.callback" => callback_url,
          "hub.topic" => topic_url,
          "hub.mode" => mode,
          "hub.verify" => verify
        })
      end

      def feed_topic_url(channel_id)
        "https://www.youtube.com/xml/feeds/videos.xml?channel_id=#{channel_id}"
      end

      private

      def client_id
        require_credential!(credential(:youtube, :client_id, env: "YOUTUBE_CLIENT_ID"), "youtube.client_id")
      end

      def client_secret
        require_credential!(credential(:youtube, :client_secret, env: "YOUTUBE_CLIENT_SECRET"), "youtube.client_secret")
      end

      # Google token endpoint — form-encoded; returns a flat { error:, error_description: }
      # on failure (notably invalid_grant when a refresh token is revoked → re-auth).
      def token_post(body)
        conn = Faraday.new(url: TOKEN) do |f|
          f.request :url_encoded
          f.response :json, content_type: /\bjson/
          f.request :retry,
                    max: 2, interval: 0.4, backoff_factor: 2,
                    retry_statuses: Vendors::Base::RETRY_STATUSES,
                    methods: %i[post]
          f.adapter Faraday.default_adapter
        end
        response = conn.post("/token", body)
        unless response.success?
          parsed = response.body
          klass = invalid_grant?(parsed) ? Vendors::Base::AuthenticationError : Vendors::Base::Error
          raise klass.new(token_error_message(parsed), status: response.status, body: parsed)
        end
        response.body
      end

      def invalid_grant?(body)
        body.is_a?(Hash) && body["error"] == "invalid_grant"
      end

      def token_error_message(body)
        return "#{body["error"]}: #{body["error_description"]}" if body.is_a?(Hash) && body["error"]

        "OAuth token request failed"
      end

      def json_get_data(path, **params)
        conn = build_connection(DATA, auth_token: @access_token)
        handle(conn.get(path) { |req| req.params.update(params) })
      end

      # Faraday with bearer auth and no JSON request middleware (raw byte bodies).
      def raw_connection
        Faraday.new do |f|
          f.headers["Authorization"] = "Bearer #{@access_token}" if @access_token
          f.adapter Faraday.default_adapter
        end
      end

      def upload_connection(content_type)
        Faraday.new(url: DATA) do |f|
          f.headers["Authorization"] = "Bearer #{@access_token}" if @access_token
          f.headers["Content-Type"] = content_type
          f.response :json, content_type: /\bjson/
          f.adapter Faraday.default_adapter
        end
      end

      def raise_for_status(response)
        return if response.success?

        handle(response)
      end
    end
  end
end
