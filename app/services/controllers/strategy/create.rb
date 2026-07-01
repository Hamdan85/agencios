# frozen_string_literal: true

module Controllers
  module Strategy
    # Start (or resume) a planning session for a project. Managers+ only, since
    # the plan fans out into real tickets.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        project = workspace.projects.find(@params[:project_id])
        authorize!(project, :update?)

        session = Operations::Strategy::Start.call(project: project, user: user)
        { strategy_session: serialize(session, StrategySessionSerializer) }
      end
    end
  end
end
