# frozen_string_literal: true

module Api
  module V1
    class MeController < BaseController
      def show = render_ok(Controllers::Me::Show.call)
    end
  end
end
