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
      # Ints default to 0. Returns nil when there is nothing to read; raises when
      # the read failed outright. (instagram.md §7b / facebook.md §7d.)
      class SyncInsights
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        # Returns nil when there is nothing to read (no external post yet) and
        # RAISES when every vendor call failed — the caller must be able to tell
        # "this post genuinely scored zero" from "we could not read it", because
        # persisting the latter as zeros leaves a permanent hole in the chart.
        def call
          return nil if @post.external_post_id.blank?

          if @social_account.provider_instagram?
            instagram_metrics
          else
            facebook_metrics
          end
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
        #
        # The two halves are attempted INDEPENDENTLY on purpose. Insights metric
        # names churn constantly (the whole post_impressions* family was retired),
        # and when that call dies it must not discard the engagement numbers we
        # already hold — that is exactly how likes/comments/shares silently went
        # to zero for every Facebook post. Only a total failure raises.
        def facebook_metrics
          engagement, engagement_error = attempt do
            GetPostEngagement.call(social_account: @social_account, post_id: @post.external_post_id)
          end
          insights_body, insights_error = attempt do
            GetPostInsights.call(social_account: @social_account, post_id: @post.external_post_id)
          end
          raise(engagement_error || insights_error) if engagement.nil? && insights_body.nil?

          engagement ||= {}
          insights = index_insights(insights_body || {})

          {
            reach: int(insights['post_impressions_unique']),
            views: pick(insights, 'post_views', 'post_impressions', 'post_video_views'),
            likes: int(engagement.dig('reactions', 'summary', 'total_count')),
            comments: int(engagement.dig('comments', 'summary', 'total_count')),
            shares: int(engagement.dig('shares', 'count')),
            saves: 0,
            raw: { 'engagement' => engagement, 'insights' => insights }
          }
        end

        # Runs one Graph call, converting a vendor failure into [nil, error] so a
        # dead half can't take the healthy one down with it. Auth failures are NOT
        # caught: a finished token is an ACCOUNT-level problem the operation layer
        # must act on, not something to paper over per post.
        def attempt
          [yield, nil]
        rescue Vendors::Base::AuthenticationError
          raise
        rescue Vendors::Base::Error => e
          Rails.logger.warn(
            "[Meta::SyncInsights] post ##{@post.id} (#{@social_account.provider}) " \
            "media=#{@post.external_post_id}: #{e.message}"
          )
          [nil, e]
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

        def int(value)
          value.to_i
        end

        # First of `names` that actually came back. The reach/views families are
        # in flux across Graph versions, so we take the surviving metric rather
        # than summing names that overlap (a video's impressions and its views
        # would otherwise be counted twice).
        def pick(values, *names)
          name = names.find { |n| values[n] }
          name ? int(values[name]) : 0
        end
      end
    end
  end
end
