# frozen_string_literal: true

module Api
  module V1
    class McpConnectorController < BaseController
      def show   = render_ok(Controllers::McpConnector::Show.call)
      def rotate = render_ok(Controllers::McpConnector::Rotate.call)
    end
  end
end
