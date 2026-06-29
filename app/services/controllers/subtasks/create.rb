# frozen_string_literal: true

module Controllers
  module Subtasks
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        subtask = Operations::Subtasks::Create.call(
          ticket: ticket,
          title: @params.require(:subtask).require(:title),
          assignee_id: @params.dig(:subtask, :assignee_id),
          due_date: @params.dig(:subtask, :due_date)
        )
        { subtask: serialize(subtask, SubtaskSerializer) }
      end
    end
  end
end
