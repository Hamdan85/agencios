# frozen_string_literal: true

module Vendors
  module Postgate
    module Actions
      # Uniform seam entrypoint — analytics for a published Post through PostGate.
      # Pinterest has no stored hourly snapshots (Pin insights only exist live —
      # PostGate's /live-stats), so pinterest accounts read that instead; every
      # other PostGate network reads the stored, append-only snapshot list and
      # takes the newest snapshot for this post.
      #
      # Returns { reach:, views:, likes:, comments:, shares:, saves:, raw: }, or
      # {} when there is nothing to read yet (no postgate_post_id, or no
      # snapshot/target data returned).
      class SyncInsights
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          return {} if @post.postgate_post_id.blank?

          @social_account.provider_pinterest? ? from_live_stats : from_post_stats
        end

        private

        def from_live_stats
          body = Vendors::Postgate::Client.new.live_stats(@post.postgate_post_id)
          snapshot = Array(body['data']).first
          return {} if snapshot.blank?

          metrics = snapshot['metrics'] || {}
          {
            reach: int(metrics['impressions']),
            views: int(metrics['impressions']),
            likes: 0,
            comments: 0,
            shares: 0,
            saves: int(metrics['saved']),
            raw: snapshot
          }
        end

        def from_post_stats
          body = Vendors::Postgate::Client.new.post_stats(post_ids: @post.postgate_post_id)
          snapshot = newest(Array(body['data']))
          return {} if snapshot.blank?

          # Code defensively for both nesting styles the API may return: metrics
          # nested under a `metrics` key (per the AnalyticsMetrics schema), or
          # flattened directly onto the snapshot.
          metrics = snapshot['metrics'] || snapshot
          {
            reach: int(metrics['reach']),
            views: int(metrics['impressions']),
            likes: int(metrics['likes']),
            comments: int(metrics['comments']),
            shares: int(metrics['shares']),
            saves: int(metrics['saved']),
            raw: snapshot
          }
        end

        # Append-only snapshots — the newest by captured timestamp (falls back to
        # array order when no recognizable timestamp field is present).
        def newest(snapshots)
          return nil if snapshots.blank?

          snapshots.max_by { |s| timestamp(s) } || snapshots.last
        end

        def timestamp(snapshot)
          value = snapshot['captured_at'] || snapshot['timestamp'] || snapshot['recorded_at']
          value.present? ? Time.zone.parse(value.to_s) : Time.at(0)
        rescue ArgumentError
          Time.at(0)
        end

        def int(value) = value.to_i
      end
    end
  end
end
