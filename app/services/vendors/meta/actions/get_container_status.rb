# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Poll an IG media container until processing finishes — GET
      # /{creation_id}?fields=status_code,status (instagram.md §6c).
      # status_code ∈ { IN_PROGRESS | FINISHED | ERROR | EXPIRED | PUBLISHED }.
      class GetContainerStatus
        def self.call(...) = new(...).call

        def initialize(social_account:, creation_id:, client: nil)
          @social_account = social_account
          @creation_id = creation_id
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get(
            "/#{@creation_id}",
            params: { fields: "status_code,status" }
          )
        end
      end
    end
  end
end
