# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — fetches analytics for a published Post and
      # normalizes them to { reach:, views:, likes:, comments:, shares:, saves:,
      # raw: }. Branches on network:
      #   Instagram → GetMediaInsights (reach/views/likes/comments/saves/shares).
      #   Facebook  → GetPostInsights  (impressions→views, reactions→likes, etc.).
      # Ints default to 0; `raw` is the full response body. (instagram.md §7b /
      # facebook.md §7b.)
      class SyncInsights
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          return empty if @post.external_post_id.blank?

          if @social_account.provider_instagram?
            instagram_metrics
          else
            facebook_metrics
          end
        rescue Vendors::Base::Error
          empty
        end

        private

        def instagram_metrics
          body = GetMediaInsights.call(
            social_account: @social_account, media_id: @post.external_post_id
          )
          values = index_insights(body)

          {
            reach: int(values["reach"]),
            views: int(values["views"]),
            likes: int(values["likes"]),
            comments: int(values["comments"]),
            shares: int(values["shares"]),
            saves: int(values["saves"]),
            raw: body
          }
        end

        def facebook_metrics
          body = GetPostInsights.call(
            social_account: @social_account, post_id: @post.external_post_id
          )
          values = index_insights(body)
          views = int(values["post_video_views"]) + int(values["post_impressions"])
          reactions = reactions_total(values["post_reactions_by_type_total"])

          {
            reach: int(values["post_impressions_unique"]),
            views: views,
            likes: reactions,
            comments: int(values["post_comments"]),
            shares: int(values["post_shares"]),
            saves: int(values["post_saves"]),
            raw: body
          }
        end

        # Insights come back as data:[{ name:, values:[{ value: }] } | { total_value: }].
        # Reduce to a { name => value } hash, handling both shapes.
        def index_insights(body)
          Array(body["data"]).each_with_object({}) do |metric, acc|
            name = metric["name"]
            acc[name] =
              if metric.key?("total_value")
                metric.dig("total_value", "value")
              else
                Array(metric["values"]).last&.fetch("value", nil)
              end
          end
        end

        # post_reactions_by_type_total is a { like:, love:, ... } hash; sum it.
        def reactions_total(value)
          return int(value) unless value.is_a?(Hash)

          value.values.sum { |v| int(v) }
        end

        def empty
          { reach: 0, views: 0, likes: 0, comments: 0, shares: 0, saves: 0, raw: {} }
        end

        def int(value)
          value.to_i
        end
      end
    end
  end
end
