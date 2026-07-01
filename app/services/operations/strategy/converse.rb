# frozen_string_literal: true

module Operations
  module Strategy
    # One turn of the strategy-planning chat. The conversation is STREAMED (text
    # relayed live to the SSE writer); the plan itself is NOT streamed. When the
    # agent is ready it calls the lightweight `generate_plan` signal, and the
    # structured plan is produced by a separate, reliable SYNC forced-tool call
    # (#build_plan) — streaming the large plan JSON is what tripped connection
    # resets, so it's deliberately kept off the stream.
    #
    # Returns a Result { session:, proposal: } — `proposal` is the plan hash when
    # THIS turn produced one, else nil, so the controller can emit a proposal event.
    Result = Struct.new(:session, :proposal, keyword_init: true)

    class Converse < Operations::Base
      # Generous caps on the SYNC calls: with reasoning on, the model spends a
      # variable amount before the forced-tool output — too small a cap can
      # truncate the tool JSON and yield an empty result. The conversation turn
      # itself is short.
      STREAM_MAX_TOKENS   = 2048
      DECISION_MAX_TOKENS = 8000
      PLAN_MAX_TOKENS     = 16000

      def initialize(session:, content:, on_generating: nil, &on_text)
        @session = session
        @content = content.to_s.strip
        @on_text = on_text
        @on_generating = on_generating
      end

      def call
        raise Operations::Errors::Invalid, 'Mensagem vazia.' if @content.blank?

        @session.push_message(role: :user, content: @content)
        @session.save!

        @planner = Prompts::StrategyPlanner.new(
          workspace: @session.workspace,
          client: @session.project.client
        )
        @client = Vendors::Ai.client(model: Vendors::Ai.model_for('strategy_planner'))

        result = @client.stream(
          system: @planner.system,
          messages: api_messages,
          tools: Prompts::StrategyPlanner.stream_tools,
          max_tokens: STREAM_MAX_TOKENS,
          &@on_text
        )

        log_usage(result, 'strategy_planner', @client)
        apply_project_update(result)

        proposal = nil
        if plan_ready?
          @on_generating&.call # let the UI show ticket skeletons while the plan generates
          proposal = build_plan
        end
        persist_turn(result, proposal)
      end

      private

      # The stored transcript rendered as the Messages API expects, dropping any
      # blank-content turns (the API rejects empty content).
      def api_messages
        Array(@session.messages).filter_map do |m|
          content = m['content'].to_s
          next if content.blank?

          { role: m['role'], content: content }
        end
      end

      # Deterministic readiness gate: a SYNC forced-tool call decides whether to
      # generate the plan this turn. The model emits tool calls unreliably in the
      # streamed chat (~1/5), so we do NOT depend on a spontaneous signal — a forced
      # tool_choice always returns a boolean. Reasoning on: it's a judgment call and
      # not streamed, so there's no reset risk.
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
        Rails.logger.warn("[Strategy::Converse] readiness check failed: #{e.class}: #{e.message}")
        false
      end

      # SYNC, non-streaming, forced-tool call — reliable structured output. The
      # whole conversation is the context; the system prompt carries the plan rules.
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
        Rails.logger.warn("[Strategy::Converse] plan generation failed: #{e.class}: #{e.message}")
        nil
      end

      # The conversation flattened as context for the sync forced-tool calls.
      def conversation
        lines = Array(@session.messages).filter_map do |m|
          content = m['content'].to_s.strip
          next if content.blank?

          "#{m['role'] == 'assistant' ? 'ESTRATEGISTA' : 'USUÁRIO'}: #{content}"
        end
        "Conversa até aqui:\n\n#{lines.join("\n\n")}"
      end

      def persist_turn(result, proposal)
        assistant_text = result.text.presence ||
                         (proposal ? 'Proposta de plano atualizada.' : nil) ||
                         # No text and no usable plan — never leave a silent, dead turn.
                         'Não consegui finalizar o plano agora. Pode me dar um retorno rápido (período ou cadência) para eu propor?'

        @session.push_message(role: :assistant, content: assistant_text) if assistant_text.present?
        if proposal
          @session.proposed_plan = proposal
          @session.status = 'proposed'
        end
        @session.save!

        Result.new(session: @session, proposal: proposal)
      end

      # If the agent called update_project this turn, apply it to the project.
      def apply_project_update(result)
        tool = tool_named(result, Prompts::StrategyPlanner::UPDATE_PROJECT_TOOL)
        input = tool && tool[:input]
        return unless input.is_a?(Hash) && input.compact.present?

        Operations::Projects::Update.call(project: @session.project, attributes: input)
      rescue StandardError => e
        Rails.logger.warn("[Strategy::Converse] project update failed: #{e.class}: #{e.message}")
      end

      def tool_named(result, name)
        Array(result.tools).find { |t| t.is_a?(Hash) && t[:name].to_s == name.to_s }
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
