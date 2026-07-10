# frozen_string_literal: true

module Api
  module V1
    class ReportsController < BaseController
      def index = render_ok(Controllers::Reports::Index.call(params:))
      def show  = render_ok(Controllers::Reports::Show.call(params:))
      def send_to_client = render_ok(Controllers::Reports::Send.call(params:))

      def pdf
        result = Controllers::Reports::Pdf.call(params:)
        send_data result[:bytes], filename: result[:filename], type: 'application/pdf', disposition: 'inline'
      end
    end
  end
end
