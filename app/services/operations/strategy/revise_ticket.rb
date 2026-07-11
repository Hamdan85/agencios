# frozen_string_literal: true

module Operations
  module Strategy
    # Edit ONE ticket, off the request. Two targets, same "ghost until applied" rule:
    #   * a PROPOSED card (key "t3") → regenerate that not-yet-created card in place.
    #   * an EXISTING ticket (key "#123") → stage an `update` op ghost carrying the
    #     new fields; only Operations::Strategy::Apply writes them to the real ticket.
    # Broadcasts `ticket_revising` (the row glows) then `ticket_drafted` (updates) —
    # every other card is untouched.
    class ReviseTicket < Operations::Base
      include TurnHelpers

      CARD_MAX_TOKENS = 2000

      def initialize(session:, key:, instruction:)
        @session = session
        @key = key.to_s.strip
        @instruction = instruction.to_s
      end

      def call
        return revise_existing_ticket if real_ticket_key?

        return unless target_card

        Broadcaster.strategy_session(@session, 'ticket_revising', key: @key)

        card = I18n.with_locale(workspace_locale(@session.workspace)) do
          build_card(cards_context(@session),
                     I18n.t('operations.strategy.revise_ticket.directive_proposed', key: @key, instruction: @instruction))
        end
        return Broadcaster.strategy_session(@session, 'plan_failed') unless card

        merged = card.merge('key' => @key, 'state' => 'ready')
        replace_card(merged)
        Broadcaster.strategy_session(@session, 'ticket_drafted', key: @key, card: merged)
      end

      private

      def real_ticket_key? = @key.match?(/\A#\d+\z/)

      def ticket_id = @key[/\d+/]&.to_i

      # Edit an already-created ticket: build the updated card from its current
      # values + the instruction, and stage it as an `update` op ghost.
      def revise_existing_ticket
        ticket = @session.project.tickets.find_by(id: ticket_id)
        return unless ticket

        card = I18n.with_locale(workspace_locale(@session.workspace)) do
          build_card(ticket_context(ticket),
                     I18n.t('operations.strategy.revise_ticket.directive_existing', instruction: @instruction))
        end
        return Broadcaster.strategy_session(@session, 'plan_failed') unless card

        stage_op_card(@session, card.merge(
          'key' => "r#{ticket.id}", 'op' => 'update', 'ticket_id' => ticket.id, 'state' => 'ready'
        ))
      end

      def ticket_context(ticket)
        I18n.t('operations.strategy.revise_ticket.ticket_context',
               key: @key, title: ticket.display_title, creative_type: ticket.creative_type,
               channels: Array(ticket.channels).join('/'), priority: ticket.priority,
               date: ticket.scheduled_at&.iso8601)
      end

      def target_card
        Array(@session.proposed_plan&.dig('tickets')).find { |c| c['key'] == @key }
      end

      def build_card(context, directive_line)
        client = ai_client('strategy_revise')
        result = client.generate(
          system: planner(@session).system,
          prompt: "#{conversation(@session)}\n\n#{context}\n\n#{directive_line}",
          tool: Prompts::StrategyPlanner.card_tool,
          max_tokens: CARD_MAX_TOKENS
        )
        log_usage(@session, result, 'strategy_revise', client)

        card = result.tool_input
        card if card.is_a?(Hash) && card['title'].to_s.present?
      rescue StandardError => e
        Rails.logger.warn("[Strategy::ReviseTicket] revise failed: #{e.class}: #{e.message}")
        nil
      end

      def replace_card(new_card)
        plan = @session.proposed_plan
        plan['tickets'] = Array(plan['tickets']).map { |c| c['key'] == @key ? new_card : c }
        @session.proposed_plan = plan
        @session.save!
      end
    end
  end
end
