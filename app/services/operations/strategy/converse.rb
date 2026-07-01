# frozen_string_literal: true

module Operations
  module Strategy
    # One turn of the strategy-planning chat: append the user's message, stream
    # the senior social-media agent's reply, and persist the assistant turn.
    # Text deltas are relayed live to the given block (the SSE writer); when the
    # agent calls the `propose_content_plan` tool, the structured plan is stored
    # on the session (`proposed_plan`, status → proposed).
    #
    # Returns a Result { session:, proposal: } — `proposal` is the plan hash when
    # THIS turn produced one, else nil, so the controller can emit a proposal
    # event.
    Result = Struct.new(:session, :proposal, keyword_init: true)

    class Converse < Operations::Base
      # A full multi-week plan (many tickets, each with a checklist) serializes to
      # a large tool-call JSON — keep this high so the JSON never gets truncated
      # mid-object (a cut-off tool call parses to nothing = a dead turn).
      MAX_TOKENS = 8000

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

        planner = Prompts::StrategyPlanner.new(
          workspace: @session.workspace,
          client: @session.project.client
        )

        result = Vendors::Anthropic::Client.new.stream(
          system: planner.system,
          messages: api_messages,
          tools: Prompts::StrategyPlanner.tools,
          max_tokens: MAX_TOKENS,
          # Fire the moment the model starts building the CONTENT PLAN (not other
          # tools), so the UI can show ticket skeletons while the JSON streams.
          on_tool_start: ->(name) { @on_generating&.call if name.to_s == Prompts::StrategyPlanner::TOOL_NAME },
          &@on_text
        )

        log_usage(result)
        apply_project_update(result)
        persist_turn(result)
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
        proposal = extract_proposal(result)
        assistant_text = result.text.presence ||
                         (proposal ? 'Proposta de plano atualizada.' : nil) ||
                         # No text and no usable plan (e.g. a tool call truncated by
                         # the token limit) — never leave a silent, dead turn.
                         'Não consegui finalizar o plano agora. Pode me dar um retorno rápido (período ou cadência) para eu propor?'

        @session.push_message(role: :assistant, content: assistant_text) if assistant_text.present?
        if proposal
          @session.proposed_plan = proposal
          @session.status = 'proposed'
        end
        @session.save!

        Result.new(session: @session, proposal: proposal)
      end

      # The captured plan tool call's input (the one with tickets), if present.
      def extract_proposal(result)
        tool = tool_named(result, Prompts::StrategyPlanner::TOOL_NAME)
        input = tool && tool[:input]
        return nil unless input.is_a?(Hash) && Array(input['tickets']).any?

        input
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

      def log_usage(result)
        Operations::Ai::LogUsage.call(
          provider: AiUsageLog::PROVIDER_ANTHROPIC,
          operation: 'strategy_planner',
          model: result.model,
          usage: result.usage,
          subject: @session.project,
          workspace: @session.workspace,
          user: @session.user
        )
      end
    end
  end
end
