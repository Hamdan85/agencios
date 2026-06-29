# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # DELETE /rest/posts/{urlencoded-urn} with X-RestLi-Method: DELETE.
      # Idempotent; success = 204.
      # See docs/integrations/linkedin.md §6 "Other ops".
      class DeletePost
        def self.call(...) = new(...).call

        def initialize(social_account:, post_urn:)
          @social_account = social_account
          @post_urn = post_urn
        end

        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          client.rest_delete("/rest/posts/#{Vendors::Linkedin::Client.encode_urn(@post_urn)}")
          true
        end
      end
    end
  end
end
