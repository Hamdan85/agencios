# frozen_string_literal: true

module Controllers
  module Strategy
    # Discard a proposed plan without applying it — the session is marked
    # `discarded` so it no longer surfaces on the project. A fresh planner run
    # starts a new session.
    class Discard < Base
      def initialize(params:)
        @params = params
      end

      def call
        session = workspace.strategy_sessions.find(@params[:id])
        authorize!(session.project, :update?)

        session.update!(status: "discarded")
        { strategy_session: serialize(session, StrategySessionSerializer) }
      end
    end
  end
end
