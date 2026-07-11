# frozen_string_literal: true

module Controllers
  module Creatives
    # DELETE /creatives/:id — workspace-level delete (no ticket scope required).
    class WorkspaceDestroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        workspace.creatives.find(@params[:id]).destroy!
        { message: I18n.t('api.creatives.removed') }
      end
    end
  end
end
