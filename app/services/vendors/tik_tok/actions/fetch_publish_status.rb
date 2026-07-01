# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Polls the publish status of a video/photo post (§6.3).
      # data.status enum: PROCESSING_UPLOAD | PROCESSING_DOWNLOAD | SEND_TO_USER_INBOX |
      #                   PUBLISH_COMPLETE | FAILED.
      # Note the TikTok spelling typo: `publicaly_available_post_id` (a list, present
      # only once a public post clears moderation). Returns the raw `data` hash.
      class FetchPublishStatus
        def self.call(...) = new(...).call

        def initialize(social_account:, publish_id:)
          @social_account = social_account
          @publish_id = publish_id
        end

        def call
          body = Vendors::TikTok::Client
                 .new(access_token: @social_account.user_access_token)
                 .fetch_status(publish_id: @publish_id)
          body['data'] || {}
        end
      end
    end
  end
end
