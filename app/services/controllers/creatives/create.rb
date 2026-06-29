# frozen_string_literal: true

module Controllers
  module Creatives
    # Upload a creative (source: uploaded) and attach its asset files.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        creative = Operations::Creatives::Create.call(
          ticket: ticket,
          creative_type: @params.require(:creative_type),
          source: :uploaded,
          caption: @params[:caption],
          metadata: @params[:metadata]&.permit!&.to_h || {}
        )
        attach_assets(creative)
        { creative: serialize(creative, CreativeSerializer) }
      end

      private

      def attach_assets(creative)
        files = @params[:assets]
        return if files.blank?

        creative.assets.attach(files)
      end
    end
  end
end
