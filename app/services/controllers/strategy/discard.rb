# frozen_string_literal: true

module Controllers
  module Strategy
    # Discard a proposed plan without applying it. The session is ETERNAL (one per
    # project) — discarding only drops the pending proposal and returns the chat to
    # `active`; the conversation and its memory continue.
    class Discard < Base
      def initialize(params:)
        @params = params
      end

      def call
        session = workspace.strategy_sessions.find(@params[:id])
        authorize!(session.project, :update?)

        session.update!(status: 'active', proposed_plan: {})
        { strategy_session: serialize(session, StrategySessionSerializer) }
      end
    end
  end
end
