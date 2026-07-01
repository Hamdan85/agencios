# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # MANDATORY before every post (§6.0) — TikTok verifies this in review.
      # Returns the creator_info `data`:
      #   creator_avatar_url, creator_username, creator_nickname,
      #   privacy_level_options (offer ONLY these to the user),
      #   comment_disabled, duet_disabled, stitch_disabled,
      #   max_video_post_duration_sec.
      class QueryCreatorInfo
        def self.call(...) = new(...).call

        def initialize(social_account)
          @social_account = social_account
        end

        def call
          body = Vendors::TikTok::Client
                 .new(access_token: @social_account.user_access_token)
                 .query_creator_info
          body['data'] || {}
        end
      end
    end
  end
end
