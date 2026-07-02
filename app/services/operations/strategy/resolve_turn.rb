# frozen_string_literal: true

module Operations
  module Strategy
    # Runs one strategy TURN off the request (Sidekiq). A forced-tool router reads
    # the conversation (+ any proposed cards) and decides the next action, then
    # dispatches it. Reliable because the decision is a forced tool_choice, not a
    # spontaneous streamed tool call.
    #
    #   generate_plan → GeneratePlan (build the whole batch, stream cards)
    #   add_tickets   → AddTickets (append NEW cards to a running project)
    #   revise_ticket → ReviseTicket (edit ONE card / existing ticket)
    #   remove_ticket → RemoveTicket (stage a real ticket's removal as a ghost)
    #   wait          → nothing (still conversing)
    class ResolveTurn < Operations::Base
      include TurnHelpers

      ACTION_MAX_TOKENS = 1024

      def initialize(session:)
        @session = session
      end

      def call
        case decide['action']
        when 'generate_plan'
          generate_plan
        when 'add_tickets'
          AddTickets.call(session: @session, instruction: @action['instruction'].to_s)
        when 'revise_ticket'
          revise
        when 'remove_ticket'
          remove
        end
      end

      private

      # A full (re)plan is only ever built for an EMPTY project. On a project that
      # already has real tickets, `generate_plan` would replace the whole plan and
      # its Apply would DISCARD the existing (possibly scheduled/published) tickets —
      # so we refuse it here (the safety net behind the router prompt) and let the
      # user make changes with add/revise/remove instead. A not-yet-applied proposed
      # plan on an empty project is still safe to regenerate.
      def generate_plan
        return if @session.project.tickets.exists?

        GeneratePlan.call(session: @session)
      end

      def revise
        key = @action['ticket_key'].to_s
        return if key.blank?

        ReviseTicket.call(session: @session, key: key, instruction: @action['instruction'].to_s)
      end

      def remove
        key = @action['ticket_key'].to_s
        return if key.blank?

        RemoveTicket.call(session: @session, key: key)
      end

      def decide
        client = ai_client('strategy_action')
        result = client.generate(
          system: 'Você decide a próxima ação do planejamento de conteúdo a partir da conversa, ' \
                  'do plano proposto e dos tickets que o projeto já tem.',
          prompt: "#{conversation(@session)}\n\n#{cards_context(@session)}\n\n" \
                  "#{project_tickets_context(@session)}\n\nDecida a ação chamando a ferramenta.",
          tool: Prompts::StrategyPlanner.action_tool,
          max_tokens: ACTION_MAX_TOKENS
        )
        log_usage(@session, result, 'strategy_action', client)
        @action = result.tool_input.is_a?(Hash) ? result.tool_input : { 'action' => 'wait' }
      rescue StandardError => e
        Rails.logger.warn("[Strategy::ResolveTurn] #{e.class}: #{e.message}")
        @action = { 'action' => 'wait' }
      end
    end
  end
end
