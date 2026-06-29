# frozen_string_literal: true

module Api
  module V1
    class BoardController < BaseController
      # GET /api/v1/board — columns keyed by status with serialized cards.
      def index
        render_ok(Controllers::Board::Index.call(params:))
      end
    end
  end
end
