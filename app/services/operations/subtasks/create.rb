# frozen_string_literal: true

module Operations
  module Subtasks
    class Create < Operations::Base
      def initialize(ticket:, title:, assignee_id: nil, due_date: nil, position: nil, estimate_hours: nil)
        @ticket = ticket
        @title = title
        @assignee_id = assignee_id
        @due_date = due_date
        @position = position
        @estimate_hours = estimate_hours
      end

      def call
        subtask = Subtask.create!(
          workspace_id: @ticket.workspace_id,
          ticket: @ticket,
          title: @title,
          assignee_id: @assignee_id,
          due_date: @due_date,
          estimate_hours: @estimate_hours,
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
          title_key: 'push.subtask_assigned.title',
          body: subtask.title,
          path: "/tickets/#{@ticket.id}"
        )

        assignee = subtask.assignee
        return if assignee.email.blank? || assignee.id == Current.user&.id

        SubtaskMailer.assigned(subtask: subtask, assignee: assignee, actor: Current.user).deliver_later
      end

      def next_position
        (@ticket.subtasks.maximum(:position) || -1) + 1
      end
    end
  end
end
