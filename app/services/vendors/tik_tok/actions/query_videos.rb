# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Refreshes metrics for videos we already track via POST /v2/video/query/ (§7.2).
      # Same fields as ListVideos, filtered by a list of video ids. Scope: video.list.
      # Returns the raw `data` hash: { videos: [...] }.
      class QueryVideos
        def self.call(...) = new(...).call

        def initialize(social_account:, video_ids:, fields: Vendors::TikTok::Actions::ListVideos::FIELDS)
          @social_account = social_account
          @video_ids = Array(video_ids)
          @fields = Array(fields)
        end

        def call
          body = Vendors::TikTok::Client
                 .new(access_token: @social_account.user_access_token)
                 .video_query(fields: @fields.join(","), video_ids: @video_ids)
          body["data"] || {}
        end
      end
    end
  end
end
