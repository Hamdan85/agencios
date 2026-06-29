# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB video Resumable Upload — Phase 1 START. POST /{page_id}/videos with
      # upload_phase=start + file_size (facebook.md §6d). Returns
      # { video_id, upload_session_id, start_offset, end_offset }.
      class StartVideoUpload
        def self.call(...) = new(...).call

        def initialize(social_account:, file_size:, client: nil)
          @social_account = social_account
          @file_size = file_size
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/videos",
            params: { upload_phase: "start", file_size: @file_size }
          )
        end
      end
    end
  end
end
