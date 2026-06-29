# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB Page photo — POST /{page_id}/photos (facebook.md §6b/§6c).
      # published=true posts immediately (returns id + post_id); published=false
      # uploads an unpublished photo to attach later via CreateFeedPost
      # (multi-photo gallery), returning just { "id" => media_fbid }.
      class CreatePagePhoto
        def self.call(...) = new(...).call

        def initialize(social_account:, url:, caption: nil, published: true, client: nil)
          @social_account = social_account
          @url = url
          @caption = caption
          @published = published
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/photos",
            params: {
              url: @url,
              caption: @caption,
              published: @published
            }
          )
        end
      end
    end
  end
end
