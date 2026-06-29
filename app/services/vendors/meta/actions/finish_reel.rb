# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB Reels — Step 4 FINISH / publish. POST /{page_id}/video_reels with
      # upload_phase=finish + video_state (facebook.md §6e). Call only after
      # processing completes. video_state ∈ { PUBLISHED | DRAFT | SCHEDULED }.
      # Returns { success: true }.
      class FinishReel
        def self.call(...) = new(...).call

        def initialize(social_account:, video_id:, description: nil, video_state: "PUBLISHED",
                       scheduled_publish_time: nil, client: nil)
          @social_account = social_account
          @video_id = video_id
          @description = description
          @video_state = video_state
          @scheduled_publish_time = scheduled_publish_time
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/video_reels",
            params: {
              video_id: @video_id,
              upload_phase: "finish",
              video_state: @video_state,
              description: @description,
              scheduled_publish_time: @scheduled_publish_time
            }
          )
        end
      end
    end
  end
end
