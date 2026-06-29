# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG publishing quota — GET /{ig_user_id}/content_publishing_limit
      # (instagram.md §9). Don't hardcode the cap; query it. `quota_usage` = posts
      # used in the rolling 24h window; `config.quota_total` = the cap.
      # Check before every publish; error code 9 = limit hit.
      class GetPublishingLimit
        def self.call(...) = new(...).call

        def initialize(social_account:, client: nil)
          @social_account = social_account
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get(
            "/#{@social_account.ig_user_id}/content_publishing_limit",
            params: { fields: "config,quota_usage" }
          )
        end
      end
    end
  end
end
