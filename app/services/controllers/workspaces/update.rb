# frozen_string_literal: true

module Controllers
  module Workspaces
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        workspace.update!(workspace_params)
        { workspace: serialize(workspace, WorkspaceSerializer) }
      end

      private

      def workspace_params
        @params.require(:workspace).permit(
          :name, :timezone, :locale, :brand_voice, :default_handle,
          :brand_primary_color, :brand_secondary_color
        )
      end
    end
  end
end
