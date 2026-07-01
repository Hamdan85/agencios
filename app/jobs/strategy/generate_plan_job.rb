# frozen_string_literal: true

module Strategy
  # Runs the slow plan decision + build for a strategy turn off the request, then
  # pushes the result to the client over Action Cable. Enqueued by
  # Operations::Strategy::Converse after each conversational turn.
  class GeneratePlanJob < ApplicationJob
    queue_as :default

    def perform(session_id)
      session = StrategySession.find_by(id: session_id)
      return unless session

      Operations::Strategy::GeneratePlan.call(session: session)
    end
  end
end
