# frozen_string_literal: true

module Operations
  module Strategy
    # The heavy half of a strategy turn, run OFF the HTTP request (Sidekiq): decide
    # whether the conversation is ready for a plan and, if so, build the structured
    # plan. Both are non-streamed forced-tool calls with reasoning on — together
    # they take 100-230s, which is why they can't sit inside the request: a
    # streaming POST held that long gets severed by the CDN (Cloudflare/QUIC).
    #
    # Progress is pushed to the client over Action Cable (`strategy_session_<id>`):
    #   - `plan_generating` — a plan IS being built this turn (UI shows skeletons)
    #   - `proposal_ready`  — the plan (persisted as `proposed_plan`, status proposed)
    #   - `plan_failed`     — readiness said yes but the build produced nothing
    # A turn that isn't ready for a plan settles silently (no broadcast).
    class GeneratePlan < Operations::Base
      # Generous caps: with reasoning on, the model spends a variable amount before
      # the forced-tool output — too small a cap truncates the tool JSON to empty.
      DECISION_MAX_TOKENS = 8000
      PLAN_MAX_TOKENS     = 16000

      def initialize(session:)
        @session = session
        @planner = Prompts::StrategyPlanner.new(
          workspace: @session.workspace,
          client: @session.project.client
        )
      end

      def call
        return unless plan_ready?

        # A plan is coming: tell the UI to clear any stale proposal and show the
        # "building…" skeletons while the (slow) plan tool-call runs.
        Broadcaster.strategy_session(@session, 'plan_generating')

        plan = build_plan
        if plan
          @session.proposed_plan = with_card_keys(plan)
          @session.status = 'proposed'
          @session.save!
          Broadcaster.strategy_session(@session, 'proposal_ready', plan: @session.proposed_plan)
        else
          Broadcaster.strategy_session(@session, 'plan_failed')
        end
      end

      private

      # Give every card a stable `key` (so the table can patch a single row and, in
      # later slices, stream/revise it) and a `state` the UI shimmers on. Generation
      # is still all-at-once here, so cards land `ready`.
      def with_card_keys(plan)
        cards = Array(plan['tickets']).each_with_index.map do |card, i|
          card.merge('key' => card['key'].presence || "t#{i + 1}", 'state' => 'ready')
        end
        plan.merge('tickets' => cards)
      end

      # Deterministic readiness gate: a forced-tool call decides whether to generate
      # the plan this turn. The model emits tool calls unreliably in free chat, so we
      # never depend on a spontaneous signal — a forced tool_choice always returns a
      # boolean.
      def plan_ready?
        client = Vendors::Ai.client(model: Vendors::Ai.model_for('strategy_planner'))
        result = client.generate(
          system: 'Você decide se o planejamento de conteúdo já pode ser gerado a partir da conversa abaixo.',
          prompt: conversation,
          tool: Prompts::StrategyPlanner.decision_tool,
          max_tokens: DECISION_MAX_TOKENS,
          reasoning: true
        )
        log_usage(result, 'strategy_planner', client)
        result.tool_input.is_a?(Hash) && result.tool_input['ready'] == true
      rescue StandardError => e
        Rails.logger.warn("[Strategy::GeneratePlan] readiness check failed: #{e.class}: #{e.message}")
        false
      end

      # Non-streaming forced-tool call — reliable structured output. The whole
      # conversation is the context; the system prompt carries the plan rules.
      def build_plan
        plan_client = Vendors::Ai.client(model: Vendors::Ai.model_for('strategy_plan'))
        result = plan_client.generate(
          system: @planner.system,
          prompt: "#{conversation}\n\nGere o plano de conteúdo agora, chamando a ferramenta.",
          tool: Prompts::StrategyPlanner.plan_tool,
          max_tokens: PLAN_MAX_TOKENS,
          reasoning: true
        )
        log_usage(result, 'strategy_plan', plan_client)

        plan = result.tool_input
        plan if plan.is_a?(Hash) && Array(plan['tickets']).any?
      rescue StandardError => e
        Rails.logger.warn("[Strategy::GeneratePlan] plan generation failed: #{e.class}: #{e.message}")
        nil
      end

      # The conversation flattened as context for the forced-tool calls.
      def conversation
        lines = Array(@session.messages).filter_map do |m|
          content = m['content'].to_s.strip
          next if content.blank?

          "#{m['role'] == 'assistant' ? 'ESTRATEGISTA' : 'USUÁRIO'}: #{content}"
        end
        "Conversa até aqui:\n\n#{lines.join("\n\n")}"
      end

      def log_usage(result, operation, client)
        Operations::Ai::LogUsage.call(
          provider: client.provider_key,
          operation: operation,
          model: result.model,
          usage: result.usage,
          cost_cents: result.usage.is_a?(Hash) ? result.usage['cost_cents'] : nil,
          subject: @session.project,
          workspace: @session.workspace,
          user: @session.user
        )
      end
    end
  end
end
