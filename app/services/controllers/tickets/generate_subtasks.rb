# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/generate_subtasks — turn the brief/scope into a production
    # subtask checklist via Claude (the "Gerar checklist com IA" action). Lives in
    # the Subtasks panel so it is available regardless of the current status.
    class GenerateSubtasks < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:id])
        created = Operations::Ai::BuildScope.call(ticket: ticket)
        { subtasks: serialize_collection(created, SubtaskSerializer) }
      end
    end
  end
end
