# frozen_string_literal: true

module Controllers
  module Generations
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        scope = workspace.generations.order(created_at: :desc)
        scope = scope.where(kind: @params[:kind]) if @params[:kind].present?
        { generations: serialize_collection(scope.limit(50), GenerationSerializer) }
      end
    end
  end
end
