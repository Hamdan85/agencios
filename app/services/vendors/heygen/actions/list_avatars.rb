# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # List available avatars + talking-photos. `GET /v2/avatars` →
      # `{ error, data: { avatars: [...], talking_photos: [...] } }`.
      #
      # Returns a Hash `{ avatars:, talking_photos: }`. This list is large,
      # paginated, and not exhaustive — cache it and refresh periodically.
      #
      # See docs/integrations/heygen.md §4.
      class ListAvatars
        def self.call(...) = new(...).call

        def initialize(client: nil)
          @client = client || Client.new
        end

        def call
          body = @client.get("/v2/avatars")
          data = body["data"] || {}
          {
            avatars: data["avatars"] || [],
            talking_photos: data["talking_photos"] || []
          }
        end
      end
    end
  end
end
