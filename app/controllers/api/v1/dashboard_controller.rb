# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      def index
        render_ok(Controllers::Dashboard::Index.call)
      end
    end
  end
end
