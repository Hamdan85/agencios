# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG single-image container — POST /{ig_user_id}/media (instagram.md §6a).
      # Returns { "id" => creation_id }.
      class CreateMediaContainer
        def self.call(...) = new(...).call

        def initialize(social_account:, image_url:, caption: nil, alt_text: nil, client: nil)
          @social_account = social_account
          @image_url = image_url
          @caption = caption
          @alt_text = alt_text
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.ig_user_id}/media",
            params: {
              image_url: @image_url,
              caption: @caption,
              alt_text: @alt_text
            }
          )
        end
      end
    end
  end
end
