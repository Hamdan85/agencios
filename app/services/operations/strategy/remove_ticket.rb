# frozen_string_literal: true

module Operations
  module Strategy
    # Stage the REMOVAL of one existing ticket as a ghost, WITHOUT deleting anything
    # yet. Removing is destructive, so it follows the same "ghost until applied"
    # rule as every other change: the removal lands as a struck-through ghost card
    # (`op: 'remove'`) in the append plan and only Operations::Strategy::Apply — the
    # user clicking "Aplicar" — actually deletes the ticket. That apply IS the
    # confirmation of the destructive action.
    #
    # `key` is the ticket reference from the router: "#<id>" (a real ticket) or a
    # proposed card key ("t3"), in which case we just drop that not-yet-created card.
    class RemoveTicket < Operations::Base
      include TurnHelpers

      def initialize(session:, key:)
        @session = session
        @key = key.to_s.strip
      end

      def call
        return drop_proposed_card if proposed_card_key?

        ticket = target_ticket
        # Unknown/stale reference → settle the drawer's waiting state instead of
        # ending the turn silently.
        return Broadcaster.strategy_session(@session, 'turn_wait') unless ticket

        stage_op_card(@session, {
                        'key' => "r#{ticket.id}", 'op' => 'remove', 'ticket_id' => ticket.id,
                        'title' => ticket.display_title, 'creative_type' => ticket.creative_type,
                        'channels' => Array(ticket.channels), 'scheduled_at' => ticket.scheduled_at&.iso8601,
                        'state' => 'ready'
                      })
      end

      private

      def proposed_card_key? = @key.match?(/\At\d+\z/)

      def ticket_id = @key[/\A#?(\d+)\z/, 1]&.to_i

      def target_ticket
        id = ticket_id
        id && @session.project.tickets.find_by(id: id)
      end

      # Dropping a still-proposed (never-created) card just removes it from the plan.
      def drop_proposed_card
        plan = @session.proposed_plan
        return Broadcaster.strategy_session(@session, 'turn_wait') unless plan.is_a?(Hash)

        remaining = Array(plan['tickets']).reject { |c| c['key'] == @key }
        return Broadcaster.strategy_session(@session, 'turn_wait') if remaining.size == Array(plan['tickets']).size

        persist_append(@session, remaining)
        Broadcaster.strategy_session(@session, 'additions_ready')
      end
    end
  end
end
