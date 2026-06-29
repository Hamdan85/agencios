# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB Reels — Step 1 START session. POST /{page_id}/video_reels with
      # upload_phase=start (facebook.md §6e). Returns
      # { video_id, upload_url } (upload_url points at the rupload host).
      class StartReelUpload
        def self.call(...) = new(...).call

        def initialize(social_account:, client: nil)
          @social_account = social_account
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/video_reels",
            params: { upload_phase: "start" }
          )
        end
      end
    end
  end
end
