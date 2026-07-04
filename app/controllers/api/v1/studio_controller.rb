# frozen_string_literal: true

module Api
  module V1
    # Creative studio: the type picker + brand context + recent generations, and
    # standalone generation (no ticket required). Guests cannot generate.
    class StudioController < BaseController
      def index = render_ok(Controllers::Studio::Index.call)

      # POST /studio/generate — body { kind, params }
      def generate = render_created(Controllers::Studio::Generate.call(params:))

      # POST /studio/improve_prompt — the "melhorar esse prompt" wand
      def improve_prompt = render_ok(Controllers::Studio::ImprovePrompt.call(params:))
    end
  end
end
