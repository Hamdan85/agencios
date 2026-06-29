# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB Page webhook subscription — POST /{page_id}/subscribed_apps with
      # subscribed_fields (facebook.md §8). Connects the Page to the app's webhook
      # for feed/mention events.
      class SubscribePageWebhooks
        def self.call(...) = new(...).call

        DEFAULT_FIELDS = "feed,mention"

        def initialize(social_account:, subscribed_fields: DEFAULT_FIELDS, client: nil)
          @social_account = social_account
          @subscribed_fields = subscribed_fields
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/subscribed_apps",
            params: { subscribed_fields: @subscribed_fields }
          )
        end
      end
    end
  end
end
