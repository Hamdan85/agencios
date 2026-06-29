# frozen_string_literal: true

module Controllers
  module Clients
    # Stateless AI synthesis of a positioning statement from the wizard inputs,
    # called before the client exists. Gated to client creators (managers+).
    class PositioningPreview < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Client, :create?)
        result = Operations::Ai::SynthesizePositioning.call(
          inputs: positioning_inputs, name: @params[:name].presence
        )
        { positioning: result }
      end

      private

      def positioning_inputs
        @params.permit(POSITIONING_PERMIT).to_h
      end
    end
  end
end
