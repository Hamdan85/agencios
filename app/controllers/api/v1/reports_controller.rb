# frozen_string_literal: true

module Api
  module V1
    class ReportsController < BaseController
      def index = render_ok(Controllers::Reports::Index.call(params:))
      def show  = render_ok(Controllers::Reports::Show.call(params:))
      def send_to_client = render_ok(Controllers::Reports::Send.call(params:))
    end
  end
end
