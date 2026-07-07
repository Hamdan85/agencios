# frozen_string_literal: true

module Operations
  module Creatives
    # Creates a Creative on the active workspace. The ticket is optional — the
    # creative studio can create standalone creatives not yet attached to a ticket.
    class Create < Operations::Base
      def initialize(creative_type:, ticket: nil, client: nil, source: :uploaded, status: nil, provider: nil,
                     caption: nil, metadata: {}, name: nil)
        @ticket = ticket
        @client = client
        @creative_type = creative_type
        @source = source
        @status = status
        @provider = provider
        @caption = caption
        @metadata = metadata || {}
        @name = name
      end

      def call
        creative = workspace.creatives.new(
          ticket: @ticket,
          client: @client || @ticket&.project&.client,
          creative_type: @creative_type,
          source: @source,
          provider: @provider,
          caption: @caption,
          metadata: @metadata,
          # A human name so the client approval portal shows a meaningful piece
          # name (never the raw type key). Defaults to the type's label.
          name: @name.presence || default_name
        )
        creative.status = @status if @status
        creative.save!
        creative
      end

      private

      def default_name
        ::Creatives.spec_for(@creative_type)&.dig(:label) || @creative_type.to_s
      end
    end
  end
end
