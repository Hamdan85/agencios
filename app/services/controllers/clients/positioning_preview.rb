# frozen_string_literal: true

module Controllers
  module Clients
    # AI-first positioning preview: the client describes the brand in free text
    # (`brief`) and the model fills the structured positioning fields. Stateless —
    # called before the client exists. Gated to client creators (managers+).
    class PositioningPreview < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Client, :create?)
        result = Operations::Ai::SynthesizePositioning.call(
          brief: @params[:brief].to_s, name: @params[:name].presence
        )
        { positioning: result }
      end
    end
  end
end
