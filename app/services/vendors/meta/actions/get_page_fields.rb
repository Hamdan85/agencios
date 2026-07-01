# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB page fields (current follower count is a FIELD; prefer followers_count
      # over the deprecated fan_count) — GET /{page_id}?fields=... (facebook.md §7a).
      class GetPageFields
        def self.call(...) = new(...).call

        DEFAULT_FIELDS = 'followers_count,fan_count,name'

        def initialize(social_account:, fields: DEFAULT_FIELDS, client: nil)
          @social_account = social_account
          @fields = fields
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get("/#{@social_account.page_id}", params: { fields: @fields })
        end
      end
    end
  end
end
