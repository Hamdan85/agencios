# frozen_string_literal: true

module Operations
  module Tickets
    # Puts a ticket into the "alert" state and generates a task for the team when
    # something breaks at posting time (a failed publish: missing creative, a
    # disconnected network, an API error). The task carries the failure context so
    # whoever picks it up knows what to fix. The detailed reason also lives on a
    # system Note (written by the caller). Idempotent-ish: it won't stack a second
    # open task for the same reason.
    class RaiseAlert < Operations::Base
      def initialize(ticket:, reason:, task_title: nil)
        @ticket = ticket
        @reason = reason.to_s.strip.presence || 'Falha na postagem'
        @task_title = task_title.to_s.strip.presence || "Resolver: #{@reason}"
      end

      def call
        @ticket.update!(alert_reason: @reason[0, 255])
        create_task
        Broadcaster.ticket(@ticket, 'alert_raised', reason: @ticket.alert_reason)
        Broadcaster.board(@ticket.workspace_id, 'ticket_alert', ticket_id: @ticket.id)
        @ticket
      end

      private

      def create_task
        title = @task_title[0, 255]
        # Don't pile up duplicate open tasks for the same failure.
        return if @ticket.subtasks.open.exists?(title: title)

        Operations::Subtasks::Create.call(
          ticket: @ticket,
          title: title,
          assignee_id: (@ticket.assignee_id || @ticket.created_by_id)
        )
      end
    end
  end
end
