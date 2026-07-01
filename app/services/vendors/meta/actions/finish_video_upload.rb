# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB video Resumable Upload — Phase 3 FINISH. POST /{page_id}/videos with
      # upload_phase=finish + metadata (facebook.md §6d). Returns { success: true }.
      class FinishVideoUpload
        def self.call(...) = new(...).call

        def initialize(social_account:, upload_session_id:, title: nil, description: nil, client: nil)
          @social_account = social_account
          @upload_session_id = upload_session_id
          @title = title
          @description = description
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/videos",
            params: {
              upload_phase: 'finish',
              upload_session_id: @upload_session_id,
              title: @title,
              description: @description
            }
          )
        end
      end
    end
  end
end
