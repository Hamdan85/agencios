# frozen_string_literal: true

module Controllers
  module Clients
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        workspace.clients.find(@params[:id]).destroy!
        { message: "Cliente removido." }
      end
    end
  end
end
