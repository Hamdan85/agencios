# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Reads the user's public videos + per-video engagement metrics via the
      # Display API POST /v2/video/list/ (§7.2). Scope: video.list.
      #
      # Returns the raw `data` hash: { videos: [...], cursor:, has_more: }.
      # Each video carries id, create_time, like_count, comment_count, share_count,
      # view_count (plus title/description/cover_image_url/share_url).
      class ListVideos
        FIELDS = %w[
          id title video_description duration cover_image_url share_url embed_link
          create_time like_count comment_count share_count view_count
        ].freeze

        def self.call(...) = new(...).call

        def initialize(social_account:, max_count: 20, cursor: 0, fields: FIELDS)
          @social_account = social_account
          @max_count = max_count
          @cursor = cursor
          @fields = Array(fields)
        end

        def call
          body = client.video_list(fields: @fields.join(','), max_count: @max_count, cursor: @cursor)
          body['data'] || {}
        end

        private

        def client
          Vendors::TikTok::Client.new(access_token: @social_account.user_access_token)
        end
      end
    end
  end
end
