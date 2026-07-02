# frozen_string_literal: true

module Operations
  module Strategy
    # Shared AI-turn plumbing for the off-request strategy jobs (ResolveTurn,
    # GeneratePlan, ReviseTicket): the planner prompt, the AI client, the flattened
    # conversation + current-cards context, and usage logging.
    module TurnHelpers
      private

      def planner(session)
        @planner ||= Prompts::StrategyPlanner.new(
          workspace: session.workspace, client: session.project.client
        )
      end

      def ai_client(operation = 'strategy_planner')
        Vendors::Ai.client(model: Vendors::Ai.model_for(operation))
      end

      # The stored transcript flattened as context for the forced-tool calls.
      def conversation(session)
        lines = Array(session.messages).filter_map do |m|
          content = m['content'].to_s.strip
          next if content.blank?

          "#{m['role'] == 'assistant' ? 'ESTRATEGISTA' : 'USUÁRIO'}: #{content}"
        end
        "Conversa até aqui:\n\n#{lines.join("\n\n")}"
      end

      # The current proposed cards, so the router can target a revise by `key`.
      def cards_context(session)
        cards = Array(session.proposed_plan&.dig('tickets'))
        return 'Ainda não há plano proposto.' if cards.empty?

        lines = cards.map do |c|
          "#{c['key']}: #{c['title']} (#{c['creative_type']}, #{Array(c['channels']).join('/')}, #{c['scheduled_at']})"
        end
        "Plano atual (para revisar UM ticket, use a key):\n#{lines.join("\n")}"
      end

      # The project's ALREADY-created tickets — so the router can tell a running
      # project (→ add_tickets) from an empty one (→ generate_plan), and the add
      # flow knows what NOT to duplicate.
      def project_tickets_context(session)
        tickets = session.project.tickets.order(:scheduled_at).limit(60)
        return 'O projeto ainda não tem tickets criados.' if tickets.empty?

        lines = tickets.map do |t|
          format = t.creative_type.presence || Array(t.try(:creative_types)).join('/')
          "- #{t.display_title} (#{format}, #{t.scheduled_at&.iso8601})"
        end
        "Tickets que o projeto JÁ tem (#{tickets.size}) — NÃO os recrie; para acrescentar " \
          "novos use add_tickets:\n#{lines.join("\n")}"
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
