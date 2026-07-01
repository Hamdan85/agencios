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

        # A plan is applied as a full rewrite: the proposed plan is always the
        # COMPLETE plan, so re-applying an edited one drops the previous batch and
        # recreates it (rather than duplicating). Hand-made tickets are untouched.
        discard_previous_batch!

        tickets = Array(@session.proposed_plan['tickets']).map { |spec| build_ticket(spec) }

        @session.update!(status: 'applied')
        Broadcaster.board(@session.workspace.id, 'strategy_applied',
                          project_id: @session.project_id, count: tickets.size)
        tickets
      end

      private

      # Delete the tickets a previous apply of THIS session created, so an edited
      # plan replaces them instead of stacking a duplicate set. Reuses the bulk
      # destroy op (cascades subtasks/creatives/posts + broadcasts the removal).
      def discard_previous_batch!
        ids = @session.tickets.pluck(:id)
        return if ids.empty?

        Operations::Tickets::BulkDestroy.call(@session.workspace, ids, user: @user)
      end

      # Ideation fields the planner fills per ticket (mirrors Tickets::Fields
      # ideation keys); carried into the ticket's ideation view via UpdateFields.
      IDEATION_KEYS = %w[brief objective target_persona content_pillar format_hypothesis].freeze

      def build_ticket(spec)
        # Never post in the past — if the planner scheduled a date already gone,
        # nudge it to today so the ticket (and its runway) stay sane.
        scheduled_at = parse_time(spec['scheduled_at'])
        scheduled_at = Time.current if scheduled_at&.past?
        post_date = scheduled_at&.to_date

        # The ticket is born in IDEAÇÃO with its ideation content, plus the strategy
        # delimiters the planner decided: creative type, channels and posting date.
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
            strategy_session_id: @session.id,
            fields: ideation_fields(spec)
          }
        )

        Array(spec['subtasks']).each do |sub|
          Operations::Subtasks::Create.call(
            ticket: ticket,
            title: sub['title'],
            due_date: subtask_due(post_date, sub['lead_offset_days']),
            estimate_hours: sub['estimate_hours']
          )
        end

        ticket
      end

      # All planner-provided ideation fields (brief + objective + persona + pillar
      # + format), so the ticket's Ideação view opens fully populated.
      def ideation_fields(spec)
        IDEATION_KEYS.each_with_object({}) do |key, acc|
          value = spec[key].to_s.strip
          acc[key] = value if value.present?
        end
      end

      # Back-schedule a task: due `lead_offset_days` before the posting date, but
      # never in the past (a lead time longer than the runway would land behind).
      def subtask_due(post_date, lead_offset_days)
        return nil if post_date.nil?

        [post_date - lead_offset_days.to_i, Date.current].max
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
