# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Uniform seam entrypoint: full X publish flow for a Post.
      #
      #   upload media (chunked) if a creative is attached
      #   -> POST /2/tweets with text [+ media_ids]
      #   -> { external_post_id: tweet id, permalink: https://x.com/i/web/status/<id> }
      #
      # Raises on failure. See docs/integrations/x-twitter.md §6.
      class PublishPost
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          media_ids = upload_media

          result = Vendors::X::Actions::CreatePost.call(
            social_account: @social_account,
            text: @post.caption.to_s,
            media_ids: media_ids
          )

          tweet_id = result.fetch(:id)
          raise Vendors::Base::Error, 'X returned no tweet id' if tweet_id.blank?

          { external_post_id: tweet_id, permalink: "https://x.com/i/web/status/#{tweet_id}" }
        end

        private

        # Uploads the first attached creative asset (image or video) and returns
        # the media_ids array (empty for text-only).
        def upload_media
          asset = first_asset
          return [] unless asset

          bytes = asset.download
          content_type = asset.content_type.to_s
          category = media_category(content_type)

          media_id = Vendors::X::Actions::UploadMedia.call(
            social_account: @social_account,
            bytes: bytes,
            media_type: content_type.presence || 'application/octet-stream',
            media_category: category
          )
          [media_id]
        end

        def first_asset
          creative = @post.publishable_creative
          creative&.assets&.first
        end

        def media_category(content_type)
          if content_type.start_with?('video')
            'tweet_video'
          elsif content_type == 'image/gif'
            'tweet_gif'
          else
            'tweet_image'
          end
        end
      end
    end
  end
end
