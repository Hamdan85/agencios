# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Photo / carousel Direct Post via the unified content/init endpoint (§6.4).
      #
      #   Vendors::TikTok::Actions::PublishPhoto.call(
      #     social_account:, post_info:, photo_images: [url, ...], photo_cover_index: 0
      #   )
      #
      # photo_images: up to 35 publicly accessible JPEG/WEBP URLs (PNG is rejected);
      # photos always use PULL_FROM_URL (domain must be verified). Returns publish_id.
      class PublishPhoto
        MAX_IMAGES = 35

        def self.call(...) = new(...).call

        def initialize(social_account:, post_info:, photo_images:, photo_cover_index: 0, post_mode: 'DIRECT_POST')
          @social_account = social_account
          @post_info = post_info
          @photo_images = Array(photo_images).first(MAX_IMAGES)
          @photo_cover_index = photo_cover_index
          @post_mode = post_mode
        end

        def call
          body = client.init_content(payload)
          (body['data'] || {})['publish_id']
        end

        private

        def client
          Vendors::TikTok::Client.new(access_token: @social_account.user_access_token)
        end

        def payload
          {
            media_type: 'PHOTO',
            post_mode: @post_mode, # DIRECT_POST (video.publish) | MEDIA_UPLOAD (video.upload)
            post_info: @post_info,
            source_info: {
              source: 'PULL_FROM_URL',
              photo_cover_index: @photo_cover_index,
              photo_images: @photo_images
            }
          }
        end
      end
    end
  end
end
