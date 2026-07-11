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

        base = pending_append_cards(@session)
        new_cards = build_additions(base)
        return Broadcaster.strategy_session(@session, 'plan_failed') if new_cards.blank?

        persist_append(@session, base + new_cards)
        new_cards.each do |card|
          sleep STAGGER
          Broadcaster.strategy_session(@session, 'ticket_drafted', key: card['key'], card: card)
        end
        Broadcaster.strategy_session(@session, 'additions_ready')
      end

      private

      def build_additions(base)
        client = ai_client('strategy_plan')
        ask = @instruction.present? ? ": #{@instruction}" : '.'
        prompt = I18n.with_locale(workspace_locale(@session.workspace)) do
          "#{conversation(@session)}\n\n#{project_tickets_context(@session)}\n\n" \
            "#{I18n.t('operations.strategy.add_tickets.instruction', ask: ask)}"
        end
        result = client.generate(
          system: planner(@session).system,
          prompt: prompt,
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

      # Fresh `t<n>` keys that don't collide with the pending create cards (only
      # `t`-prefixed keys count — op cards use `r<id>`), so row-level revise stays
      # unambiguous. Each new card is a `create` op, additive.
      def with_new_keys(tickets, base)
        offset = base.filter_map { |c| c['key'].to_s[/\At(\d+)\z/, 1]&.to_i }.max.to_i
        tickets.each_with_index.filter_map do |card, i|
          next unless card.is_a?(Hash) && card['title'].to_s.present?

          card.merge('key' => "t#{offset + i + 1}", 'op' => 'create', 'state' => 'ready', 'additive' => true)
        end
      end
    end
  end
end
