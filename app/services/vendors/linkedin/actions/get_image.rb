# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/images/{urn} — poll an uploaded image until status: AVAILABLE.
      # Uploads process async; SYNCHRONOUS_UPLOAD is not supported.
      # See docs/integrations/linkedin.md §6b.
      class GetImage
        def self.call(...) = new(...).call

        def initialize(social_account:, image_urn:)
          @social_account = social_account
          @image_urn = image_urn
        end

        # Returns the parsed asset body (includes "status").
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          client.rest_get("/rest/images/#{Vendors::Linkedin::Client.encode_urn(@image_urn)}")
        end
      end
    end
  end
end
