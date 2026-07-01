# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG Story container — POST /{ig_user_id}/media with media_type=STORIES
      # (instagram.md §6). Used to reshare a just-published Reel's video to the
      # account's story (the combined post flow). Accepts a hosted video_url (or
      # image_url for a still story). Returns { "id" => creation_id }.
      class CreateStoryContainer
        def self.call(...) = new(...).call

        def initialize(social_account:, video_url: nil, image_url: nil, client: nil)
          @social_account = social_account
          @video_url = video_url
          @image_url = image_url
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          params = { media_type: 'STORIES' }
          if @video_url.present?
            params[:video_url] = @video_url
          else
            params[:image_url] = @image_url
          end

          @client.post("/#{@social_account.ig_user_id}/media", params:)
        end
      end
    end
  end
end
