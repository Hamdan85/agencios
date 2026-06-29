# frozen_string_literal: true

module Api
  module V1
    # Read-only generation history for the active workspace.
    class GenerationsController < BaseController
      def index = render_ok(Controllers::Generations::Index.call(params:))
      def show  = render_ok(Controllers::Generations::Show.call(params:))
    end
  end
end
