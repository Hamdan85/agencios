# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # OAuth Step 5 (alternative) — resolve the linked Instagram business
      # account id from a Page id. GET /{page_id}?fields=instagram_business_account
      # (instagram.md §4).
      class GetLinkedInstagramAccount
        def self.call(...) = new(...).call

        def initialize(page_id:, page_access_token:, client: nil)
          @page_id = page_id
          @page_access_token = page_access_token
          @client = client || Vendors::Meta::Client.new
        end

        # Returns { "instagram_business_account" => { "id" => ig_user_id }, "id" => page_id }.
        def call
          @client.get(
            "/#{@page_id}",
            params: { fields: 'instagram_business_account{id,username}' },
            token: @page_access_token
          )
        end
      end
    end
  end
end
