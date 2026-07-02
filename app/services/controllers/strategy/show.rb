# frozen_string_literal: true

module Controllers
  module Strategy
    # The current (resumable) planning session for a project, or null when none
    # has been started. Read-only — does not create a session.
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        project = workspace.projects.find(@params[:project_id])
        authorize!(project, :show?)

        # A project has exactly ONE (eternal) session — surface it whatever its
        # state; a pending proposal is just its `proposed` status.
        session = project.strategy_sessions.recent.first
        { strategy_session: session && serialize(session, StrategySessionSerializer) }
      end
    end
  end
end
