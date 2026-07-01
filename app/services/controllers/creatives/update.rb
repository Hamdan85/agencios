# frozen_string_literal: true

module Controllers
  module Creatives
    # PATCH /creatives/:id — rename or re-assign client.
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        creative = workspace.creatives.find(@params[:id])
        authorize!(creative, :update?)

        permitted = @params.slice(:name, :client_id)
        permitted[:client_id] = permitted[:client_id].presence # allow clearing with null
        creative.update!(**permitted.compact)
        { creative: serialize(creative, CreativeSerializer) }
      end
    end
  end
end
