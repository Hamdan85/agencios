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

      Operations::Strategy::ResolveTurn.call(session: session)
    end
  end
end
