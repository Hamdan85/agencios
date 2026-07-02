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
        # Only a plan AWAITING DECISION is appliable. The session is eternal (one
        # per project), so a stale plan kept on an `active` session must never be
        # re-runnable — a second POST /apply after the flow settled would re-run
        # side effects (including the full-plan batch discard).
        raise Operations::Errors::Invalid, 'Nenhum plano proposto para aplicar.' unless
          @session.status_proposed? && @session.proposed_plan?

        # A full plan is applied as a rewrite: the proposed plan is the COMPLETE
        # plan, so re-applying an edited one drops the previous batch and recreates
        # it (rather than duplicating). An ADDITIVE/OPS plan (mode `append`) instead
        # carries only the changes to ACRESCENTAR — new pieces (`create`), edits
        # (`update`) and removals (`remove`) of specific tickets — and never discards
        # the existing batch. Hand-made tickets are untouched either way.
        discard_previous_batch! unless additive?

        created = []
        Array(@session.proposed_plan['tickets']).each do |spec|
          case spec['op']
          when 'remove' then remove_ticket(spec)
          when 'update' then update_ticket(spec)
          else created << build_ticket(spec)
          end
        end

        # The session is eternal — applying returns it to `active` (conversing),
        # keeping the plan as a record of what was materialized. The status_proposed
        # guard above is what makes the kept plan inert.
        @session.update!(status: 'active')
        Broadcaster.board(@session.workspace.id, 'strategy_applied',
                          project_id: @session.project_id, count: created.size)
        created
      end

      private

      # An additive/ops plan only carries changes to apply — keep the existing batch.
      def additive?
        @session.proposed_plan['mode'] == 'append'
      end

      # Materialize a staged edit onto the real ticket (scoped to this project, so a
      # stale/foreign id is silently ignored). Status is never touched here.
      def update_ticket(spec)
        ticket = @session.project.tickets.find_by(id: spec['ticket_id'])
        return unless ticket

        # Only overwrite fields the staged card actually carries — a missing/blank
        # field keeps the ticket's current value (never wipe channels to []).
        params = { title: spec['title'].presence, creative_type: spec['creative_type'].presence,
                   priority: spec['priority'].presence }.compact
        params[:channels] = Array(spec['channels']).compact_blank if Array(spec['channels']).compact_blank.any?
        params[:scheduled_at] = parse_time(spec['scheduled_at']) if spec['scheduled_at'].present?

        Operations::Tickets::Update.call(ticket: ticket, params: params)
      end

      # Materialize a staged removal — hard-delete the ticket via the canonical op.
      def remove_ticket(spec)
        id = spec['ticket_id']
        return if id.blank?

        Operations::Tickets::BulkDestroy.call(@session.workspace, [id], user: @user)
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
