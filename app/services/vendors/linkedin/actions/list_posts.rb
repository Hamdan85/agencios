# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/posts?q=author&author={urn} — list posts by author.
      # Needs r_organization_social (org) or r_member_social (restricted, member).
      # See docs/integrations/linkedin.md API reference table.
      class ListPosts
        def self.call(...) = new(...).call

        def initialize(social_account:, author_urn:)
          @social_account = social_account
          @author_urn = author_urn
        end

        # Returns the parsed body ({ "elements" => [...] }).
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          client.rest_get(
            "/rest/posts",
            q: "author", author: @author_urn
          )
        end
      end
    end
  end
end
