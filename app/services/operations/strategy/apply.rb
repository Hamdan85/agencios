# frozen_string_literal: true

module Operations
  module Strategy
    # Fan out an approved `proposed_plan` into real work: one scheduled ticket per
    # planned content piece, each with a back-scheduled, estimated production
    # checklist. Reuses the canonical creators (never bare create!) so every
    # ticket/subtask side effect (notes, notifications, broadcasts) fires normally.
    class Apply < Operations::Base
      def initialize(session:, user: nil)
        @session = session
        @user = user || Current.user
      end

      def call
        raise Operations::Errors::Invalid, 'Nenhum plano proposto para aplicar.' unless @session.proposed_plan?

        # A full plan is applied as a rewrite: the proposed plan is the COMPLETE
        # plan, so re-applying an edited one drops the previous batch and recreates
        # it (rather than duplicating). An ADDITIVE plan (mode `append`) instead
        # carries ONLY new pieces to ACRESCENTAR — never discard the existing batch,
        # just create the new cards beside it. Hand-made tickets are untouched either way.
        discard_previous_batch! unless additive?

        tickets = Array(@session.proposed_plan['tickets']).map { |spec| build_ticket(spec) }

        @session.update!(status: 'applied')
        Broadcaster.board(@session.workspace.id, 'strategy_applied',
                          project_id: @session.project_id, count: tickets.size)
        tickets
      end

      private

      # An additive plan only carries new pieces to append — keep the existing batch.
      def additive?
        @session.proposed_plan['mode'] == 'append'
      end

      # Delete the tickets a previous apply of THIS session created, so an edited
      # plan replaces them instead of stacking a duplicate set. Reuses the bulk
      # destroy op (cascades subtasks/creatives/posts + broadcasts the removal).
      def discard_previous_batch!
        ids = @session.tickets.pluck(:id)
        return if ids.empty?

        Operations::Tickets::BulkDestroy.call(@session.workspace, ids, user: @user)
      end

      # The strategist may only plan content for at most one month ahead. This
      # is the authoritative guard: any far-future posting date the planner
      # proposes is clamped back into the horizon when the plan is materialized.
      PLANNING_HORIZON = 1.month

      def build_ticket(spec)
        # Never post in the past — if the planner scheduled a date already gone,
        # nudge it to today so the ticket (and its runway) stay sane. And never
        # plan beyond the one-month horizon — clamp any far-future date back in.
        scheduled_at = parse_time(spec['scheduled_at'])
        scheduled_at = Time.current if scheduled_at&.past?
        horizon = PLANNING_HORIZON.from_now
        scheduled_at = horizon if scheduled_at && scheduled_at > horizon

        # The ticket is born in IDEAÇÃO as a SLIM card — the strategy delimiters the
        # planner decided (title, format, channels, posting date). The ideation brief
        # and production checklist are filled per ticket right after creation, async.
        ticket = Operations::Tickets::Create.call(
          workspace: @session.workspace,
          user: @user,
          params: {
            project_id: @session.project_id,
            title: spec['title'],
            priority: spec['priority'].presence || 'medium',
            creative_type: spec['creative_type'],
            channels: Array(spec['channels']),
            scheduled_at: scheduled_at,
            strategy_session_id: @session.id
          }
        )

        # Fill the brief + checklist at CREATION, not during planning — one job per
        # ticket, so each real row lights up in the table until its content lands.
        ::Strategy::FillTicketJob.perform_later(ticket.id)
        ticket
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
