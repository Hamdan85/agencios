# frozen_string_literal: true

module Controllers
  module Workspaces
    class Show < Base
      def call
        { workspace: serialize(workspace, WorkspaceSerializer) }
      end
    end
  end
end
