# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — fetches analytics for a published Post and
      # normalizes them to { reach:, views:, likes:, comments:, shares:, saves:,
      # raw: }. Branches on network:
      #   Instagram → GetMediaInsights (reach/views/likes/comments/saved/shares).
      #   Facebook  → GetPostEngagement (likes/comments/shares from the post
      #               object) + GetPostInsights (reach/views, best-effort).
      # Ints default to 0. (instagram.md §7b / facebook.md §7d.)
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
        rescue Vendors::Base::Error => e
          Rails.logger.warn(
            "[Meta::SyncInsights] post ##{@post.id} (#{@social_account.provider}) " \
            "media=#{@post.external_post_id}: #{e.message}"
          )
          empty
        end

        private

        def instagram_metrics
          body = GetMediaInsights.call(
            social_account: @social_account, media_id: @post.external_post_id
          )
          values = index_insights(body)

          {
            reach: int(values['reach']),
            views: int(values['views']),
            likes: int(values['likes']),
            comments: int(values['comments']),
            shares: int(values['shares']),
            saves: int(values['saved']),
            raw: body
          }
        end

        # Engagement (likes/comments/shares) comes from the stable post object;
        # reach/views from the resilient insights call (which drops any metric the
        # current Graph version has deprecated). saves: FB has no post-save metric.
        def facebook_metrics
          engagement = GetPostEngagement.call(
            social_account: @social_account, post_id: @post.external_post_id
          )
          insights = index_insights(
            GetPostInsights.call(
              social_account: @social_account, post_id: @post.external_post_id
            )
          )

          {
            reach: int(insights['post_impressions_unique']),
            views: int(insights['post_impressions']) + int(insights['post_video_views']),
            likes: int(engagement.dig('reactions', 'summary', 'total_count')),
            comments: int(engagement.dig('comments', 'summary', 'total_count')),
            shares: int(engagement.dig('shares', 'count')),
            saves: 0,
            raw: { 'engagement' => engagement, 'insights' => insights }
          }
        end

        # Insights come back as data:[{ name:, values:[{ value: }] } | { total_value: }].
        # Reduce to a { name => value } hash, handling both shapes.
        def index_insights(body)
          Array(body['data']).each_with_object({}) do |metric, acc|
            name = metric['name']
            acc[name] =
              if metric.key?('total_value')
                metric.dig('total_value', 'value')
              else
                Array(metric['values']).last&.fetch('value', nil)
              end
          end
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
