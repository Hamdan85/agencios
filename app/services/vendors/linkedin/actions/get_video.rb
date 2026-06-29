# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/videos/{urn} — poll an uploaded video until status: AVAILABLE.
      # See docs/integrations/linkedin.md §6c.
      class GetVideo
        def self.call(...) = new(...).call

        def initialize(social_account:, video_urn:)
          @social_account = social_account
          @video_urn = video_urn
        end

        # Returns the parsed asset body (includes "status").
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          client.rest_get("/rest/videos/#{Vendors::Linkedin::Client.encode_urn(@video_urn)}")
        end
      end
    end
  end
end
