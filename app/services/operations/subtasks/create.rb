# frozen_string_literal: true

module Operations
  module Subtasks
    class Create < Operations::Base
      def initialize(ticket:, title:, assignee_id: nil, due_date: nil, position: nil)
        @ticket = ticket
        @title = title
        @assignee_id = assignee_id
        @due_date = due_date
        @position = position
      end

      def call
        subtask = Subtask.create!(
          workspace_id: @ticket.workspace_id,
          ticket: @ticket,
          title: @title,
          assignee_id: @assignee_id,
          due_date: @due_date,
          position: @position || next_position
        )
        notify_assignee(subtask)
        subtask
      end

      private

      def notify_assignee(subtask)
        return if subtask.assignee_id.blank?

        Operations::Push::Notify.call(
          user: subtask.assignee, actor: Current.user,
          title: "Nova tarefa atribuída a você",
          body: subtask.title,
          path: "/tickets/#{@ticket.id}"
        )
      end

      def next_position
        (@ticket.subtasks.maximum(:position) || -1) + 1
      end
    end
  end
end
