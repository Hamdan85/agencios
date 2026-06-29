# frozen_string_literal: true

module Operations
  module Clients
    # Creates a Client on the active workspace (the aggregate root itself).
    class Create < Operations::Base
      PERMITTED = %i[
        name company email phone document notes status
        brand_voice default_handle brand_primary_color brand_secondary_color
      ].freeze

      def initialize(params)
        params = params.to_h.symbolize_keys
        @attributes = params.slice(*PERMITTED)
        @positioning = Client.sanitize_positioning(params[:positioning])
      end

      def call
        client = workspace.clients.new(@attributes)
        client.positioning = @positioning if @positioning.present?
        client.save!
        client
      end
    end
  end
end
