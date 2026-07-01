# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Reads account profile + stats via the Display API GET /v2/user/info/ (§7.1).
      # Only request fields whose scopes were granted, or the call errors — callers
      # pass the field set matching the account's scopes. Returns the `user` hash.
      class FetchUserInfo
        # Default field set assuming user.info.basic + .profile + .stats are granted.
        DEFAULT_FIELDS = %w[
          open_id union_id avatar_url avatar_url_100 avatar_large_url display_name
          username is_verified bio_description profile_deep_link
          follower_count following_count likes_count video_count
        ].freeze

        def self.call(...) = new(...).call

        def initialize(social_account:, fields: DEFAULT_FIELDS)
          @social_account = social_account
          @fields = Array(fields)
        end

        def call
          body = client.user_info(fields: @fields.join(','))
          body.dig('data', 'user') || {}
        end

        private

        def client
          Vendors::TikTok::Client.new(access_token: @social_account.user_access_token)
        end
      end
    end
  end
end
