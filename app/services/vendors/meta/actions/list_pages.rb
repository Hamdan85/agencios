# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # OAuth Step 4 — list the Pages the user manages, each carrying a
      # non-expiring Page access token and (if linked) the Instagram
      # business account. GET /me/accounts (instagram.md/facebook.md §4).
      class ListPages
        def self.call(...) = new(...).call

        # Pass the long-lived USER token.
        def initialize(user_access_token:, client: nil)
          @user_access_token = user_access_token
          @client = client || Vendors::Meta::Client.new
        end

        # Returns the parsed body; `data` is an array of
        # { id, name, access_token, tasks, instagram_business_account{ id, username } }.
        def call
          @client.get(
            "/me/accounts",
            params: {
              fields: "id,name,access_token,tasks,instagram_business_account{id,username}"
            },
            token: @user_access_token
          )
        end
      end
    end
  end
end
