# frozen_string_literal: true

module Operations
  module Strategy
    # One turn of the strategy-planning chat. Only the CONVERSATION happens here —
    # the assistant's reply is STREAMED live to the SSE writer and this returns in
    # seconds. The heavy plan decision + build (100-230s) is handed off to
    # Strategy::GeneratePlanJob and pushed back to the client over Action Cable
    # when ready. Holding the streaming request open for the whole plan build got
    # the connection severed by the CDN (Cloudflare/QUIC) mid-turn.
    #
    # Returns a Result { session:, proposal: } — `proposal` is always nil now (the
    # plan arrives async); the struct is kept for the controller's call shape.
    Result = Struct.new(:session, :proposal, keyword_init: true)

    class Converse < Operations::Base
      # The conversation turn itself is short; the plan-building caps live on
      # Strategy::GeneratePlan, which runs the forced-tool calls off the request.
      STREAM_MAX_TOKENS = 2048

      def initialize(session:, content:, on_generating: nil, &on_text)
        @session = session
        @content = content.to_s.strip
        @on_text = on_text
        @on_generating = on_generating # kept for call-shape compat; plan progress now flows over Action Cable
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
        persist_turn(result)

        # Decide + build the plan off the request; the proposal is broadcast over
        # Action Cable (`strategy_session_<id>`) when it's ready. Leading `::` so the
        # constant resolves to the top-level job, not Operations::Strategy::*.
        ::Strategy::GeneratePlanJob.perform_later(@session.id)

        Result.new(session: @session, proposal: nil)
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

      def persist_turn(result)
        # No streamed text means the model went straight for a tool call — leave a
        # neutral holding line so the turn is never silent; the plan lands via cable.
        assistant_text = result.text.presence ||
                         'Certo! Deixa eu montar isso e já te trago a proposta.'
        @session.push_message(role: :assistant, content: assistant_text)
        @session.save!
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
