# frozen_string_literal: true

module Operations
  module Tickets
    # Clears a ticket's "alert" state (e.g. after a clean publish, or when the team
    # resolves the issue). No-op when the ticket isn't in alert.
    class ClearAlert < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        return @ticket unless @ticket.in_alert?

        @ticket.update!(alert_reason: nil)
        Broadcaster.ticket(@ticket, 'alert_cleared')
        Broadcaster.board(@ticket.workspace_id, 'ticket_alert', ticket_id: @ticket.id)
        @ticket
      end
    end
  end
end
