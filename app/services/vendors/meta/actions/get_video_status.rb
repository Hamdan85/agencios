# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Poll FB video/Reel processing — GET /{video_id}?fields=status
      # (facebook.md §6d/§6e). status.video_status ∈ { processing | ready | error };
      # Reels report phases uploading_phase → processing_phase → publishing_phase.
      class GetVideoStatus
        def self.call(...) = new(...).call

        def initialize(social_account:, video_id:, client: nil)
          @social_account = social_account
          @video_id = video_id
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get("/#{@video_id}", params: { fields: "status" })
        end
      end
    end
  end
end
