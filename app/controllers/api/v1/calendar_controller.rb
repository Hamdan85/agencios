# frozen_string_literal: true

module Api
  module V1
    class CalendarController < BaseController
      def index
        render_ok(Controllers::Calendar::Index.call(params:))
      end
    end
  end
end
