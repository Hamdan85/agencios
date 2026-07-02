# frozen_string_literal: true

module Strategy
  # Resolves one strategy turn off the request (decide → generate plan / revise a
  # ticket / wait) and pushes results over Action Cable. Enqueued by
  # Operations::Strategy::Converse after each conversational reply.
  class PlanTurnJob < ApplicationJob
    queue_as :default

    def perform(session_id)
      session = StrategySession.find_by(id: session_id)
      return unless session

      # The drawer shows "digitando…" from here until the turn resolves — either
      # into a build (plan_started / additions_building / ticket_revising) or into
      # an explicit turn_wait — so the router's decision window is never a silent
      # gap where the agent looks idle.
      Broadcaster.strategy_session(session, 'turn_resolving')
      Operations::Strategy::ResolveTurn.call(session: session)
    rescue StandardError
      Broadcaster.strategy_session(session, 'turn_wait') if session
      raise
    end
  end
end
