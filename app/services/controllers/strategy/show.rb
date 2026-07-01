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

        # Prefer a PROPOSED session (a plan awaiting a decision) over a newer
        # active one, so a pending plan always surfaces after a reload.
        sessions = project.strategy_sessions.where.not(status: 'discarded')
        session = sessions.status_proposed.recent.first || sessions.recent.first
        { strategy_session: session && serialize(session, StrategySessionSerializer) }
      end
    end
  end
end
