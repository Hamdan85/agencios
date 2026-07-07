# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG Reels container — POST /{ig_user_id}/media with media_type=REELS
      # (instagram.md §6c). Mode A: hosted video_url. Mode B: upload_type=resumable
      # (returns an `uri` to PUT raw bytes via UploadReelBinary).
      # Returns { "id" => creation_id } (+ "uri" in resumable mode).
      class CreateReelsContainer
        def self.call(...) = new(...).call

        def initialize(social_account:, video_url: nil, caption: nil, cover_url: nil,
                       share_to_feed: true, resumable: false, client: nil)
          @social_account = social_account
          @video_url = video_url
          @caption = caption
          @cover_url = cover_url
          @share_to_feed = share_to_feed
          @resumable = resumable
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          params = {
            media_type: 'REELS',
            caption: @caption,
            cover_url: @cover_url,
            share_to_feed: @share_to_feed
          }
          if @resumable
            params[:upload_type] = 'resumable'
          else
            params[:video_url] = @video_url
          end

          @client.post("/#{@social_account.ig_user_id}/media", params:)
        end
      end
    end
  end
end
