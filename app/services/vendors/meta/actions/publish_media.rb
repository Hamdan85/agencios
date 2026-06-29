# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG publish — POST /{ig_user_id}/media_publish with the creation_id of a
      # finished container (instagram.md §6a). Returns { "id" => media_id }.
      class PublishMedia
        def self.call(...) = new(...).call

        def initialize(social_account:, creation_id:, client: nil)
          @social_account = social_account
          @creation_id = creation_id
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.ig_user_id}/media_publish",
            params: { creation_id: @creation_id }
          )
        end
      end
    end
  end
end
