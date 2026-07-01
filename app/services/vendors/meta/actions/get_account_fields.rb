# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG account fields (current follower/follows/media counts are FIELDS, not
      # insights) — GET /{ig_user_id}?fields=followers_count,... (instagram.md §7a).
      class GetAccountFields
        def self.call(...) = new(...).call

        DEFAULT_FIELDS = 'followers_count,follows_count,media_count,username'

        def initialize(social_account:, fields: DEFAULT_FIELDS, client: nil)
          @social_account = social_account
          @fields = fields
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get("/#{@social_account.ig_user_id}", params: { fields: @fields })
        end
      end
    end
  end
end
