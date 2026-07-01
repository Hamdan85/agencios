# frozen_string_literal: true

module Operations
  module Projects
    # The single authoritative "start a project" transition. Moves a `draft`
    # project into `active` and stamps its start date when one wasn't set,
    # then lets the board know it's live.
    class Start < Operations::Base
      def initialize(project:, user: nil)
        @project = project
        @user = user
      end

      def call
        @project.update!(
          status: :active,
          starts_on: @project.starts_on || Date.current
        )
        Broadcaster.board(@project.workspace_id, 'project_started', project_id: @project.id)
        @project
      end
    end
  end
end
