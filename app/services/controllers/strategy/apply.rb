# frozen_string_literal: true

module Controllers
  module Strategy
    # Approve a session's proposed plan → create the scheduled tickets + subtasks.
    class Apply < Base
      def initialize(params:)
        @params = params
      end

      def call
        session = workspace.strategy_sessions.find(@params[:id])
        authorize!(session.project, :update?)

        tickets = Operations::Strategy::Apply.call(session: session, user: user)
        {
          count: tickets.size,
          tickets: serialize_collection(tickets, TicketCardSerializer),
          strategy_session: serialize(session, StrategySessionSerializer)
        }
      end
    end
  end
end
