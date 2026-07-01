# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uniform seam entrypoint — DELETE /youtube/v3/videos?id=... (§6.6-style Data
      # API call, ~50 units; youtube.upload scope covers managing/deleting videos
      # uploaded via the API). Raises on failure.
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          raise Vendors::Base::Error, 'Post sem external_post_id.' if @post.external_post_id.blank?

          Vendors::Youtube::Client
            .new(access_token: @social_account.user_access_token)
            .delete_video(video_id: @post.external_post_id)
          true
        end
      end
    end
  end
end
