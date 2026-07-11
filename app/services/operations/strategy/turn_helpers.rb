# frozen_string_literal: true

module Operations
  module Strategy
    # Shared AI-turn plumbing for the off-request strategy jobs (ResolveTurn,
    # GeneratePlan, ReviseTicket): the planner prompt, the AI client, the flattened
    # conversation + current-cards context, and usage logging.
    module TurnHelpers
      # The session is eternal, so the stored transcript grows without bound. The
      # DB keeps everything; the AI context gets the most recent window — generous
      # enough to hold months of planning turns, bounded enough to keep the
      # forced-tool calls fast and affordable.
      CONTEXT_MESSAGES = 200

      private

      def planner(session)
        @planner ||= Prompts::StrategyPlanner.new(
          workspace: session.workspace, client: session.project.client
        )
      end

      def ai_client(operation = 'strategy_planner')
        Vendors::Ai.client(model: Vendors::Ai.model_for(operation))
      end

      # The stored transcript flattened as context for the forced-tool calls
      # (windowed to the last CONTEXT_MESSAGES turns — see above).
      def conversation(session)
        lines = Array(session.messages).last(CONTEXT_MESSAGES).filter_map do |m|
          content = m['content'].to_s.strip
          next if content.blank?

          role = I18n.t(m['role'] == 'assistant' ? 'operations.strategy.turn_helpers.role_assistant' : 'operations.strategy.turn_helpers.role_user')
          "#{role}: #{content}"
        end
        I18n.t('operations.strategy.turn_helpers.conversation', lines: lines.join("\n\n"))
      end

      # The current proposed cards, so the router can target a revise by `key`.
      def cards_context(session)
        cards = Array(session.proposed_plan&.dig('tickets'))
        return I18n.t('operations.strategy.turn_helpers.no_plan') if cards.empty?

        lines = cards.map do |c|
          "#{c['key']}: #{c['title']} (#{c['creative_type']}, #{Array(c['channels']).join('/')}, #{c['scheduled_at']})"
        end
        I18n.t('operations.strategy.turn_helpers.current_plan', lines: lines.join("\n"))
      end

      # The project's ALREADY-created tickets — so the router can tell a running
      # project (→ add_tickets) from an empty one (→ generate_plan), knows what NOT
      # to duplicate, and can target one for edit/remove by its `#<id>` reference.
      def project_tickets_context(session)
        tickets = session.project.tickets.order(:scheduled_at).limit(60)
        return I18n.t('operations.strategy.turn_helpers.no_tickets') if tickets.empty?

        lines = tickets.map do |t|
          format = t.creative_type.presence || Array(t.try(:creative_types)).join('/')
          "- ##{t.id}: #{t.display_title} (#{format}, #{t.scheduled_at&.iso8601})"
        end
        I18n.t('operations.strategy.turn_helpers.existing_tickets',
               count: tickets.size, lines: lines.join("\n"))
      end

      # Resolve the workspace's own locale so off-request turns (Sidekiq) render the
      # planner prompts and assistant notes in the workspace language.
      def workspace_locale(ws) = I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale

      # The pending additive/ops cards to stack onto (when the user is stacking
      # changes onto an already-proposed append plan that hasn't been applied), or
      # [] for a fresh set. In every other case (applied plan, or a full proposed
      # plan) we start fresh so we never re-propose already-materialized tickets.
      def pending_append_cards(session)
        plan = session.proposed_plan
        return [] unless session.status_proposed? && plan.is_a?(Hash) && plan['mode'] == 'append'

        Array(plan['tickets'])
      end

      # Persist an append plan (mode `append`) — the additive/ops proposal that lands
      # as ghosts beside the real tickets and is materialized by Apply without
      # discarding the existing batch.
      def persist_append(session, cards)
        summary = session.proposed_plan.is_a?(Hash) ? session.proposed_plan['summary'] : nil
        session.proposed_plan = { 'summary' => summary, 'tickets' => cards, 'mode' => 'append' }.compact
        session.status = 'proposed'
        session.save!
      end

      # Stage ONE op card (an update/remove targeting a real ticket) into the append
      # plan and stream it as a ghost. Replaces any prior pending op on the same
      # ticket so stacking edits on one ticket never duplicates its ghost.
      def stage_op_card(session, card)
        Broadcaster.strategy_session(session, 'additions_building')
        base = pending_append_cards(session).reject { |c| c['ticket_id'] == card['ticket_id'] }
        persist_append(session, base + [card])
        Broadcaster.strategy_session(session, 'ticket_drafted', key: card['key'], card: card)
        Broadcaster.strategy_session(session, 'additions_ready')
      end

      def log_usage(session, result, operation, client)
        Operations::Ai::LogUsage.call(
          provider: client.provider_key,
          operation: operation,
          model: result.model,
          usage: result.usage,
          cost_cents: result.usage.is_a?(Hash) ? result.usage['cost_cents'] : nil,
          subject: session.project,
          workspace: session.workspace,
          user: session.user
        )
      end
    end
  end
end
