# frozen_string_literal: true

module Operations
  module Tickets
    # Intra-column ordering: persist the new position within a status column.
    class Reorder < Operations::Base
      def initialize(ticket:, position:)
        @ticket = ticket
        @position = position.to_i
      end

      def call
        @ticket.update!(position: @position)
        Broadcaster.board(@ticket.workspace_id, 'card_moved',
                          ticket_id: @ticket.id, to: @ticket.status, position: @position)
        @ticket
      end
    end
  end
end
