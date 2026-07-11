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
        else
          # Nothing to do this turn — tell the drawer so the "digitando…" state
          # (armed by PlanTurnJob's turn_resolving) settles instead of spinning.
          Broadcaster.strategy_session(@session, 'turn_wait')
        end
      end

      private

      # A full (re)plan is only ever built for an EMPTY campaign. On a campaign
      # that already has real tickets, `generate_plan` would replace the whole plan
      # and its Apply would DISCARD the existing (possibly scheduled/published)
      # tickets — so we refuse it here (the safety net behind the router prompt).
      # The refusal is NEVER silent: the user asked for something, so the agent
      # answers in the chat with what it can do instead (add / edit / remove).
      def generate_plan
        return GeneratePlan.call(session: @session) unless @session.project.tickets.exists?

        note = I18n.with_locale(workspace_locale(@session.workspace)) do
          I18n.t('operations.strategy.resolve_turn.replan_refused')
        end
        @session.push_message(role: :assistant, content: note)
        @session.save!
        Broadcaster.strategy_session(@session, 'assistant_note', content: note)
      end

      def revise
        key = @action['ticket_key'].to_s
        return Broadcaster.strategy_session(@session, 'turn_wait') if key.blank?

        ReviseTicket.call(session: @session, key: key, instruction: @action['instruction'].to_s)
      end

      def remove
        key = @action['ticket_key'].to_s
        return Broadcaster.strategy_session(@session, 'turn_wait') if key.blank?

        RemoveTicket.call(session: @session, key: key)
      end

      def decide
        client = ai_client('strategy_action')
        system, prompt = I18n.with_locale(workspace_locale(@session.workspace)) do
          [
            I18n.t('operations.strategy.resolve_turn.decide_system'),
            "#{conversation(@session)}\n\n#{cards_context(@session)}\n\n" \
              "#{project_tickets_context(@session)}\n\n#{I18n.t('operations.strategy.resolve_turn.decide_instruction')}"
          ]
        end
        result = client.generate(
          system: system,
          prompt: prompt,
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
