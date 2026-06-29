# frozen_string_literal: true

module Controllers
  module Generations
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        generation = workspace.generations.find(@params[:id])
        { generation: serialize(generation, GenerationSerializer) }
      end
    end
  end
end
