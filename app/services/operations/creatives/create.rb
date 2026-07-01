# frozen_string_literal: true

module Operations
  module Creatives
    # Creates a Creative on the active workspace. The ticket is optional — the
    # creative studio can create standalone creatives not yet attached to a ticket.
    class Create < Operations::Base
      def initialize(creative_type:, ticket: nil, source: :uploaded, status: nil, provider: nil, caption: nil,
                     metadata: {})
        @ticket = ticket
        @creative_type = creative_type
        @source = source
        @status = status
        @provider = provider
        @caption = caption
        @metadata = metadata || {}
      end

      def call
        creative = workspace.creatives.new(
          ticket: @ticket,
          creative_type: @creative_type,
          source: @source,
          provider: @provider,
          caption: @caption,
          metadata: @metadata
        )
        creative.status = @status if @status
        creative.save!
        creative
      end
    end
  end
end
