# frozen_string_literal: true

module Controllers
  module Studio
    # POST /studio/generate — standalone generation (no ticket). Guests cannot generate.
    class Generate < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        require_credits!(kind: @params.require(:kind))
        generation = Operations::Generations::Run.call(
          workspace: workspace,
          user: user,
          kind: @params.require(:kind),
          params: studio_params
        )
        { generation: serialize(generation, GenerationSerializer) }
      end

      private

      def studio_params
        raw = @params[:params]
        return {} if raw.blank?

        raw.permit!.to_h.symbolize_keys
      end
    end
  end
end
