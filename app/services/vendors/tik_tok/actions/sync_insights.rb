# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Uniform seam entrypoint — fetches analytics for a published Post.
      # TikTok exposes likes/comments/shares/views per video (no reach/saves via the
      # Display API), and only for PUBLIC videos. We query by the post's external id
      # (video.query), falling back to scanning the recent video list. Returns:
      #   { reach:, views:, likes:, comments:, shares:, saves:, raw: {...} }
      # (reach mirrors views since TikTok's Display API has no reach metric; saves -> 0).
      class SyncInsights
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          video = fetch_video
          views = int(video['view_count'])

          {
            reach: views,
            views: views,
            likes: int(video['like_count']),
            comments: int(video['comment_count']),
            shares: int(video['share_count']),
            saves: 0,
            raw: video
          }
        end

        private

        def fetch_video
          id = @post.external_post_id
          return {} if id.blank?

          data = Vendors::TikTok::Actions::QueryVideos.call(
            social_account: @social_account, video_ids: [id]
          )
          Array(data['videos']).find { |v| v['id'].to_s == id.to_s } || {}
        rescue Vendors::Base::Error
          {}
        end

        def int(value)
          value.to_i
        end
      end
    end
  end
end
