# frozen_string_literal: true

module Controllers
  module Projects
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        workspace.projects.find(@params[:id]).destroy!
        { message: "Projeto removido." }
      end
    end
  end
end
