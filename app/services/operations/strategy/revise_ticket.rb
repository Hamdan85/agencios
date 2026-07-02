# frozen_string_literal: true

module Operations
  module Strategy
    # Regenerate ONE proposed card in place, off the request. Broadcasts
    # `ticket_revising` (the row glows) then `ticket_drafted` (the row updates) —
    # every other card is untouched.
    class ReviseTicket < Operations::Base
      include TurnHelpers

      CARD_MAX_TOKENS = 2000

      def initialize(session:, key:, instruction:)
        @session = session
        @key = key.to_s
        @instruction = instruction.to_s
      end

      def call
        return unless target_card

        Broadcaster.strategy_session(@session, 'ticket_revising', key: @key)

        card = build_card
        return Broadcaster.strategy_session(@session, 'plan_failed') unless card

        merged = card.merge('key' => @key, 'state' => 'ready')
        replace_card(merged)
        Broadcaster.strategy_session(@session, 'ticket_drafted', key: @key, card: merged)
      end

      private

      def target_card
        Array(@session.proposed_plan&.dig('tickets')).find { |c| c['key'] == @key }
      end

      def build_card
        client = ai_client('strategy_revise')
        result = client.generate(
          system: planner(@session).system,
          prompt: "#{conversation(@session)}\n\n#{cards_context(@session)}\n\n" \
                  "Revise SOMENTE o ticket #{@key} conforme o pedido: #{@instruction}\n" \
                  'Chame a ferramenta com o card atualizado (mantendo o mesmo formato de card).',
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
