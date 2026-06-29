# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG carousel CHILD container — POST /{ig_user_id}/media with
      # is_carousel_item=true (instagram.md §6b step 1). Accepts an image or a
      # video child. Returns { "id" => child_id } (up to 10 children per parent).
      class CreateCarouselItem
        def self.call(...) = new(...).call

        def initialize(social_account:, image_url: nil, video_url: nil, client: nil)
          @social_account = social_account
          @image_url = image_url
          @video_url = video_url
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          params = { is_carousel_item: true }
          if @video_url
            params[:video_url] = @video_url
            params[:media_type] = "VIDEO"
          else
            params[:image_url] = @image_url
          end

          @client.post("/#{@social_account.ig_user_id}/media", params:)
        end
      end
    end
  end
end
