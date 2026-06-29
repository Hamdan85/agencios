# frozen_string_literal: true

module Operations
  module Clients
    # Replaces a client's positioning bag. Sanitizes to Client::POSITIONING_KEYS
    # so unknown keys never reach the column. Used by the client detail page edit
    # and reusable by any caller that needs to (re)define positioning.
    class UpdatePositioning < Operations::Base
      def initialize(client:, positioning:)
        @client = client
        @positioning = Client.sanitize_positioning(positioning)
      end

      def call
        @client.update!(positioning: @positioning)
        @client
      end
    end
  end
end
