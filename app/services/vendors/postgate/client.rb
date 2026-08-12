# frozen_string_literal: true

module Vendors
  module Postgate
    # Low-level PostGate API wrapper (https://postgate.studio) — a multi-tenant
    # social publishing aggregator: profile groups, hosted account connection,
    # post creation/publishing, analytics, and webhooks across sandbox, facebook,
    # instagram, threads, linkedin, bluesky, mastodon, telegram, tiktok, youtube,
    # pinterest, google_business, and x.
    #
    # Raw HTTP only — no domain logic, no DB writes, no post-aware orchestration.
    # `Publishers::SocialPublisher` / `Operations::Posts::*` own that layer and
    # call this client (or `Vendors::Postgate::Actions::*` built on top of it).
    #
    # Auth: single app-level API key, `Authorization: Bearer <api_key>` on every
    # `/api/*` call. Key lives in Rails encrypted credentials
    # (`postgate.api_key`), with an ENV fallback for local dev.
    #
    # See docs/integrations/postgate.md.
    class Client < Vendors::Base
      BASE_URL = 'https://postgate.studio'

      class << self
        def api_key
          Rails.application.credentials.dig(:postgate, :api_key) || ENV['POSTGATE_API_KEY']
        end

        def configured?
          api_key.present?
        end
      end

      def initialize(api_key: nil)
        @api_key = api_key || self.class.api_key
        require_credential!(@api_key, 'postgate.api_key')
      end

      # --- Profile groups -------------------------------------------------------

      # POST /api/profile-groups
      def create_profile_group(name:, timezone: 'UTC')
        post('/api/profile-groups', { name: name, timezone: timezone })
      end

      # GET /api/profile-groups
      def list_profile_groups
        get('/api/profile-groups')
      end

      # DELETE /api/profile-groups/{id}
      def delete_profile_group(id)
        delete("/api/profile-groups/#{id}")
      end

      # --- Profiles (connected social accounts) ---------------------------------

      # POST /api/profiles/connect — returns { platform:, url:, expires_in: } for
      # the hosted connection flow. `return_url`'s origin must already be
      # registered via #allow_connect_origin.
      def create_connect_url(platform:, profile_group_id: nil, return_url: nil, instance_url: nil)
        post('/api/profiles/connect', {
               platform: platform,
               profile_group_id: profile_group_id,
               return_url: return_url,
               instance_url: instance_url
             }.compact)
      end

      # GET /api/profiles — filters: profile_group_id, platform
      def list_profiles(**filters)
        get('/api/profiles', filters)
      end

      # GET /api/profiles/{id}
      def get_profile(id)
        get("/api/profiles/#{id}")
      end

      # DELETE /api/profiles/{id}
      def delete_profile(id)
        delete("/api/profiles/#{id}")
      end

      # GET /api/profiles/{id}/health
      def profile_health(id)
        get("/api/profiles/#{id}/health")
      end

      # GET /api/profiles/{id}/stats
      def profile_stats(id, from: nil, to: nil)
        get("/api/profiles/#{id}/stats", from: from, to: to)
      end

      # POST /api/profiles/{id}/import — queues a backfill of posts already
      # published on the connected account (created_via=imported).
      def import_profile_posts(id)
        post("/api/profiles/#{id}/import", {})
      end

      # GET /api/profiles/{id}/boards — Pinterest boards of a connected profile.
      def list_boards(profile_id)
        get("/api/profiles/#{profile_id}/boards")
      end

      # --- Connect origins (allowed `return_url` origins) -----------------------

      # GET /api/connect-origins
      def connect_origins
        get('/api/connect-origins')
      end

      # POST /api/connect-origins
      def allow_connect_origin(origin:, label: nil)
        post('/api/connect-origins', { origin: origin, label: label }.compact)
      end

      # --- Posts ------------------------------------------------------------------

      # POST /api/posts — payload is the full body hash:
      # { post: {...}, profiles: [...], media: [...] }. `idempotency_key`, when
      # given, is sent as `Idempotency-Key` and dedupes retries for 72h.
      def create_post(payload, idempotency_key: nil)
        headers = idempotency_key.present? ? { 'Idempotency-Key' => idempotency_key } : {}
        post('/api/posts', payload, headers: headers)
      end

      # GET /api/posts/{id}
      def get_post(id)
        get("/api/posts/#{id}")
      end

      # DELETE /api/posts/{id}
      def delete_post(id)
        delete("/api/posts/#{id}")
      end

      # GET /api/posts/{id}/logs — sanitized delivery attempt timeline.
      def post_logs(id)
        get("/api/posts/#{id}/logs")
      end

      # GET /api/posts/stats — stored hourly snapshots (Pinterest excluded; see
      # #live_stats). `post_ids` is comma-joined.
      def post_stats(post_ids:, from: nil, to: nil)
        get('/api/posts/stats', post_ids: Array(post_ids).join(','), from: from, to: to)
      end

      # GET /api/posts/{id}/live-stats — Pinterest-only live provider read,
      # nothing persisted by PostGate.
      def live_stats(post_id)
        get("/api/posts/#{post_id}/live-stats")
      end

      # --- Analytics --------------------------------------------------------------

      # GET /api/analytics/timeseries — daily metric growth by platform/profile
      # group, plus a previous-period comparison.
      def analytics_timeseries(from: nil, to: nil, platform: nil, profile_id: nil, profile_group_id: nil,
                                compare: nil)
        get('/api/analytics/timeseries', {
              from: from, to: to, platform: platform,
              profile_id: profile_id, profile_group_id: profile_group_id, compare: compare
            })
      end

      # --- Platform metadata --------------------------------------------------------

      # GET /api/platforms — machine-readable per-provider capabilities.
      def platforms
        get('/api/platforms')
      end

      # GET /api/quotas — plan usage, feature entitlements, daily estimates.
      def quotas
        get('/api/quotas')
      end

      # --- Webhooks -----------------------------------------------------------------

      # GET /api/webhooks
      def list_webhooks
        get('/api/webhooks')
      end

      # POST /api/webhooks — `events` is the topic list (see docs/integrations/postgate.md).
      def create_webhook(url:, events:)
        post('/api/webhooks', { url: url, events: events })
      end

      # DELETE /api/webhooks/{id}
      def delete_webhook(id)
        delete("/api/webhooks/#{id}")
      end

      private

      def connection
        @connection ||= build_connection(BASE_URL, auth_token: @api_key)
      end

      def get(path, params = {})
        handle(connection.get(path) { |req| req.params.update(params.compact) if params.present? })
      end

      def post(path, body = {}, headers: {})
        handle(connection.post(path) do |req|
          headers.each { |key, value| req.headers[key] = value }
          req.body = body
        end)
      end

      def delete(path)
        handle(connection.delete(path))
      end
    end
  end
end
