# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # POST /rest/posts/{urlencoded-urn} with X-RestLi-Method: PARTIAL_UPDATE.
      # Only commentary, CTA label/landing page, lifecycleState, adContext are
      # editable. Success = 204.
      # See docs/integrations/linkedin.md §6 "Other ops".
      class UpdatePost
        def self.call(...) = new(...).call

        def initialize(social_account:, post_urn:, set:)
          @social_account = social_account
          @post_urn = post_urn
          @set = set
        end

        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          response = client.rest_post_raw(
            "/rest/posts/#{Vendors::Linkedin::Client.encode_urn(@post_urn)}",
            { "patch" => { "$set" => @set } },
            extra_headers: { "X-RestLi-Method" => "PARTIAL_UPDATE" }
          )
          unless response.status == 204
            raise Vendors::Base::Error.new(
              "LinkedIn update post failed", status: response.status, body: response.body
            )
          end
          true
        end
      end
    end
  end
end
