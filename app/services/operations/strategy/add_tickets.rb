# frozen_string_literal: true

module Operations
  module Strategy
    # Append NEW ticket cards to a project that already has content, WITHOUT
    # touching what's there. Unlike GeneratePlan (which replaces the whole plan and
    # is applied as a full rewrite), this proposes only the new pieces as an
    # ADDITIVE plan (`proposed_plan['mode'] = 'append'`), so they land as ghost
    # rows beside the existing real tickets and Operations::Strategy::Apply creates
    # them without discarding the previous batch.
    #
    # Streams over the same channel, but with additive events so the frontend
    # appends the new ghosts instead of wiping the table:
    #   additions_building → the composer shows "thinking" (cards NOT reset)
    #   ticket_drafted     → each new ghost row lands, one at a time
    #   additions_ready    → done (status `proposed`, mode `append`)
    class AddTickets < Operations::Base
      include TurnHelpers

      ADD_MAX_TOKENS = 3000
      STAGGER = 0.35

      def initialize(session:, instruction: '')
        @session = session
        @instruction = instruction.to_s.strip
      end

      def call
        Broadcaster.strategy_session(@session, 'additions_building')

        base = pending_additive_cards
        new_cards = build_additions(base)
        return Broadcaster.strategy_session(@session, 'plan_failed') if new_cards.blank?

        persist(base + new_cards)
        new_cards.each do |card|
          sleep STAGGER
          Broadcaster.strategy_session(@session, 'ticket_drafted', key: card['key'], card: card)
        end
        Broadcaster.strategy_session(@session, 'additions_ready')
      end

      private

      # If the user is stacking additions onto an already-proposed additive plan
      # (not yet applied), keep those pending cards and append after them. In every
      # other case (applied plan, or a full proposed plan) start a fresh additive
      # set so we never re-propose already-materialized tickets.
      def pending_additive_cards
        plan = @session.proposed_plan
        return [] unless @session.status_proposed? && plan.is_a?(Hash) && plan['mode'] == 'append'

        Array(plan['tickets'])
      end

      def build_additions(base)
        client = ai_client('strategy_plan')
        ask = @instruction.present? ? ": #{@instruction}" : '.'
        result = client.generate(
          system: planner(@session).system,
          prompt: "#{conversation(@session)}\n\n#{project_tickets_context(@session)}\n\n" \
                  "Adicione APENAS as peças NOVAS pedidas#{ask}\n" \
                  'Não repita nenhum ticket existente. Chame a ferramenta add_tickets com os cards novos.',
          tool: Prompts::StrategyPlanner.add_tool,
          max_tokens: ADD_MAX_TOKENS
        )
        log_usage(@session, result, 'strategy_plan', client)

        input = result.tool_input
        return [] unless input.is_a?(Hash)

        with_new_keys(Array(input['tickets']), base)
      rescue StandardError => e
        Rails.logger.warn("[Strategy::AddTickets] add failed: #{e.class}: #{e.message}")
        []
      end

      # Fresh keys that don't collide with the pending additive cards, so row-level
      # patch/revise stays unambiguous.
      def with_new_keys(tickets, base)
        offset = base.filter_map { |c| c['key'].to_s[/\d+/]&.to_i }.max.to_i
        tickets.each_with_index.filter_map do |card, i|
          next unless card.is_a?(Hash) && card['title'].to_s.present?

          card.merge('key' => "t#{offset + i + 1}", 'state' => 'ready', 'additive' => true)
        end
      end

      def persist(cards)
        summary = @session.proposed_plan.is_a?(Hash) ? @session.proposed_plan['summary'] : nil
        @session.proposed_plan = { 'summary' => summary, 'tickets' => cards, 'mode' => 'append' }.compact
        @session.status = 'proposed'
        @session.save!
      end
    end
  end
end
