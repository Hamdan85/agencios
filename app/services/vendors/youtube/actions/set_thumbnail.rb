# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Sets a custom thumbnail on a video via thumbnails.set (§6.6, 50 units).
      # Max 2 MB, jpeg/png, recommended 1280x720. Requires a phone-verified channel,
      # else 403. Returns the parsed response body.
      class SetThumbnail
        def self.call(...) = new(...).call

        def initialize(social_account:, video_id:, image_bytes:, content_type: 'image/jpeg')
          @social_account = social_account
          @video_id = video_id
          @image_bytes = image_bytes
          @content_type = content_type
        end

        def call
          Vendors::Youtube::Client
            .new(access_token: @social_account.user_access_token)
            .set_thumbnail(video_id: @video_id, image_bytes: @image_bytes, content_type: @content_type)
        end
      end
    end
  end
end
