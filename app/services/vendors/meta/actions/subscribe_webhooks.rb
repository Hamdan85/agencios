# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG webhook subscription — POST /{ig_user_id}/subscribed_apps with
      # subscribed_fields (instagram.md §8). Connects the IG account to the app's
      # webhook so it receives comments/mentions events.
      class SubscribeWebhooks
        def self.call(...) = new(...).call

        DEFAULT_FIELDS = "comments,mentions"

        def initialize(social_account:, subscribed_fields: DEFAULT_FIELDS, client: nil)
          @social_account = social_account
          @subscribed_fields = subscribed_fields
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.ig_user_id}/subscribed_apps",
            params: { subscribed_fields: @subscribed_fields }
          )
        end
      end
    end
  end
end
