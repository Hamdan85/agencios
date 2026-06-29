# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG carousel PARENT container — POST /{ig_user_id}/media with
      # media_type=CAROUSEL + children (instagram.md §6b step 2).
      # Returns { "id" => creation_id }.
      class CreateCarouselContainer
        def self.call(...) = new(...).call

        # child_ids: array of child container ids from CreateCarouselItem.
        def initialize(social_account:, child_ids:, caption: nil, client: nil)
          @social_account = social_account
          @child_ids = Array(child_ids)
          @caption = caption
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.ig_user_id}/media",
            params: {
              media_type: "CAROUSEL",
              children: @child_ids.join(","),
              caption: @caption
            }
          )
        end
      end
    end
  end
end
