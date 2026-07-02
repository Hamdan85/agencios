# frozen_string_literal: true

module Operations
  module Strategy
    # Builds the content-plan batch off the request and streams it to the client
    # over Action Cable, card by card, so the table fills in live:
    #   plan_started  → the table shows its (ephemeral) loading state
    #   plan_outline  → the empty ghost rows land (loading stops)
    #   ticket_drafted → each row fills in, one at a time
    #   plan_ready    → done (status `proposed`)
    #
    # The batch is SLIM — only the approval-visible fields per card (title, format,
    # channels, priority, posting date). The ideation brief + production checklist
    # are generated per ticket WHEN it's created (Operations::Ai::FillFields +
    # BuildScope via Strategy::FillTicketJob), never here.
    class GeneratePlan < Operations::Base
      include TurnHelpers

      PLAN_MAX_TOKENS = 4000
      # A small pause between cards so the "filling in" cascade is visible; the job
      # is off-request and infrequent, so the added wall-clock is harmless.
      STAGGER = 0.35

      def initialize(session:)
        @session = session
      end

      def call
        Broadcaster.strategy_session(@session, 'plan_started')

        plan = build_plan
        return Broadcaster.strategy_session(@session, 'plan_failed') unless plan

        cards = with_card_keys(plan['tickets'])
        # Empty rows first (just key + date), so the table shows skeleton rows that
        # then fill in — title, format and channels arrive per card on ticket_drafted.
        Broadcaster.strategy_session(@session, 'plan_outline',
                                     tickets: cards.map { |c| c.slice('key', 'scheduled_at') })
        persist(plan['summary'], cards)

        cards.each do |card|
          sleep STAGGER
          Broadcaster.strategy_session(@session, 'ticket_drafted', key: card['key'], card: card)
        end
        Broadcaster.strategy_session(@session, 'plan_ready')
      end

      private

      # Non-streaming forced-tool call — reliable structured output. The slim schema
      # (no briefs/subtasks) keeps this cheap and fast.
      def build_plan
        client = ai_client('strategy_plan')
        result = client.generate(
          system: planner(@session).system,
          prompt: "#{conversation(@session)}\n\nGere o plano de conteúdo agora, chamando a ferramenta.",
          tool: Prompts::StrategyPlanner.plan_tool,
          max_tokens: PLAN_MAX_TOKENS
        )
        log_usage(@session, result, 'strategy_plan', client)

        plan = result.tool_input
        plan if plan.is_a?(Hash) && Array(plan['tickets']).any?
      rescue StandardError => e
        Rails.logger.warn("[Strategy::GeneratePlan] plan generation failed: #{e.class}: #{e.message}")
        nil
      end

      # Every card gets a stable `key` (for row-level patch/revise) and a `state`
      # the UI shimmers on. Generation is all-at-once, so cards land `ready`.
      def with_card_keys(tickets)
        Array(tickets).each_with_index.map do |card, i|
          card.merge('key' => card['key'].presence || "t#{i + 1}", 'state' => 'ready')
        end
      end

      def persist(summary, cards)
        @session.proposed_plan = { 'summary' => summary, 'tickets' => cards }
        @session.status = 'proposed'
        @session.save!
      end
    end
  end
end
