# frozen_string_literal: true

module Vendors
  module Postgate
    module Actions
      # Uniform seam entrypoint for PROFILE-level analytics of a postgate-sourced
      # SocialAccount — mirrors Vendors::Meta::Actions::SyncAccountInsights's
      # return shape:
      #   { followers:, new_followers:, accounts_reached:, profile_views:,
      #     views:, story_replies:, total_interactions:, raw: }
      #
      # PostGate's profile-stats snapshots are append-only hourly reads (same
      # shape family as post stats) and don't carry every field the direct
      # vendors expose (no story-reply metric) — anything absent defaults to 0.
      # Called by Operations::Social::SyncAccountInsights.
      class SyncAccountInsights
        def self.call(...) = new(...).call

        def initialize(social_account, since: nil, until_time: nil, client: nil)
          @social_account = social_account
          @since = since
          @until_time = until_time
          @client = client || Vendors::Postgate::Client.new
        end

        def call
          return empty if @social_account.postgate_profile_id.blank?

          body = @client.profile_stats(@social_account.postgate_profile_id, from: iso(@since), to: iso(@until_time))
          snapshots = Array(body['data'])
          return empty if snapshots.blank?

          aggregate(snapshots)
        rescue Vendors::Base::Error
          empty
        end

        private

        def aggregate(snapshots)
          latest = snapshots.max_by { |s| timestamp(s) } || snapshots.last
          latest_metrics = latest['metrics'] || latest
          {
            followers: int(latest_metrics['followers']),
            new_followers: sum(snapshots, 'new_followers'),
            accounts_reached: sum(snapshots, 'reach'),
            profile_views: sum(snapshots, 'profile_views'),
            views: sum(snapshots, 'impressions'),
            story_replies: 0,
            total_interactions: sum(snapshots, 'engagements'),
            raw: { latest: latest, snapshots: snapshots }
          }
        end

        def sum(snapshots, key)
          snapshots.sum { |s| int((s['metrics'] || s)[key]) }
        end

        def timestamp(snapshot)
          value = snapshot['captured_at'] || snapshot['timestamp'] || snapshot['recorded_at']
          value.present? ? Time.zone.parse(value.to_s) : Time.at(0)
        rescue ArgumentError
          Time.at(0)
        end

        def iso(time)
          time&.iso8601
        end

        def empty
          {
            followers: 0, new_followers: 0, accounts_reached: 0, profile_views: 0,
            views: 0, story_replies: 0, total_interactions: 0, raw: {}
          }
        end

        def int(value) = value.to_i
      end
    end
  end
end
