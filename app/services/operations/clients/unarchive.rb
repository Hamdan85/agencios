# frozen_string_literal: true

module Operations
  module Clients
    # Reactivates an archived client. Its projects stay archived — restore them
    # individually so old campaigns don't flood back onto the board.
    class Unarchive < Operations::Base
      def initialize(client)
        @client = client
      end

      def call
        @client.update!(status: :active)
        @client
      end
    end
  end
end
