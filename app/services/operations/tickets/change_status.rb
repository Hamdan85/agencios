# frozen_string_literal: true

module Operations
  module Tickets
    # The SINGLE authoritative status-transition point. Never mutate ticket.status
    # with a bare update! anywhere else. Records a log + history note, refreshes
    # the status-scoped AI summary, fires status side effects, and broadcasts.
    class ChangeStatus < Operations::Base
      WORKFLOW = Ticket::WORKFLOW

      def initialize(ticket, to_status, user:, force: false, position: nil)
        @ticket = ticket
        @to_status = to_status.to_s
        @user = user
        @force = force
        @position = position
      end

      def call
        validate_status!
        from_status = @ticket.status
        return @ticket if from_status == @to_status && @position.nil?

        guard_regression!(from_status)

        ApplicationRecord.transaction do
          apply_status!(from_status)
          log_transition(from_status)
          write_history_note(from_status)
        end

        enqueue_summary
        enqueue_carry_over(from_status)
        fire_side_effects(from_status)
        broadcast(from_status)

        @ticket
      end

      private

      def validate_status!
        return if WORKFLOW.map(&:to_s).include?(@to_status)

        raise Operations::Errors::InvalidTransition, "Status inválido: #{@to_status}"
      end

      # A board drag may move backward only for managers (or force).
      def guard_regression!(from_status)
        return if @force
        return if step(@to_status) >= step(from_status)
        return if @user.nil? || @user.can_manage?(@ticket.workspace)

        raise Operations::Errors::InvalidTransition, 'Apenas gestores podem retroceder um ticket.'
      end

      def apply_status!(_from_status)
        attrs = { status: @to_status }
        attrs[:position] = @position if @position
        attrs[:published_at] = Time.current if @to_status == 'published' && @ticket.published_at.nil?
        @ticket.update!(attrs)
      end

      def log_transition(from_status)
        TicketStatusLog.create!(
          workspace_id: @ticket.workspace_id,
          ticket: @ticket,
          user: @user,
          from_status: Ticket.statuses[from_status],
          to_status: Ticket.statuses[@to_status]
        )
      end

      def write_history_note(from_status)
        Operations::Notes::Create.call(
          ticket: @ticket,
          user: nil,
          kind: :system,
          body: "Status: #{label(from_status)} → #{label(@to_status)}"
        )
      end

      # The contextual case-study summary is now surfaced ONLY on the "Concluído"
      # screen (the per-stage "Resumo IA" card was removed), so generate it just
      # when the ticket completes — not on every transition.
      def enqueue_summary
        return unless @to_status == 'done'

        SummarizeTicketJob.perform_later(@ticket.id, @to_status)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] could not enqueue summary: #{e.message}")
      end

      # Stages whose fields benefit from automatic carry-over. `retrospective` is
      # excluded — it's auto-drafted from metrics by DraftRetrospectiveJob;
      # `published`/`done` have no editable fields.
      CARRY_OVER_STATUSES = %w[scoping production scheduled].freeze

      # Forward moves carry the funnel's context into the new stage's blank fields
      # (deterministic seed + AI fill). Skip on regressions and same-step reorders.
      def enqueue_carry_over(from_status)
        return unless step(@to_status) > step(from_status)
        return unless CARRY_OVER_STATUSES.include?(@to_status)

        CarryOverFieldsJob.perform_later(@ticket.id, @to_status)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] could not enqueue carry-over: #{e.message}")
      end

      # Publishing is no longer a side effect of a board move. The posting step
      # (Operations::Tickets::Publish) creates the posts and fires publishing;
      # the ticket reaches "published" only when a post succeeds. Entering
      # `published` therefore has no publish side effect here (avoids re-posting).
      def fire_side_effects(_from_status)
        case @to_status
        when 'published'     then close_open_subtasks
        when 'retrospective' then draft_retrospective
        when 'done'          then spawn_follow_ups
        end
      end

      # Reaching "No ar" means the production work shipped — auto-close any still-open
      # subtasks so they stop lingering on assignees' My Tasks after the ticket is live.
      def close_open_subtasks
        @ticket.subtasks.open.find_each do |subtask|
          Operations::Subtasks::Update.call(subtask, done: true)
        end
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] close_open_subtasks failed: #{e.message}")
      end

      # On completion, if the retrospective recommends iterating/repeating, spawn a
      # pre-filled ideation ticket linked back to this one (iteration/repetition of).
      def spawn_follow_ups
        rec = @ticket.fields_for('retrospective')['repeat_recommendation'].to_s
        return unless %w[iterate repeat].include?(rec)

        Operations::Tickets::SpawnFollowUp.call(source: @ticket, recommendation: rec, user: @user)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] spawn_follow_ups failed: #{e.message}")
      end

      def draft_retrospective
        DraftRetrospectiveJob.perform_later(@ticket.id)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] enqueue retro failed: #{e.message}")
      end

      def broadcast(from_status)
        Broadcaster.ticket(@ticket, 'status_changed', to: @to_status, from: from_status)
        Broadcaster.board(@ticket.workspace_id, 'card_moved',
                          ticket_id: @ticket.id, to: @to_status, from: from_status, position: @ticket.position)
      end

      def step(status) = WORKFLOW.index(status.to_sym) || 0
      def label(status) = Ticket::STATUS_LABELS[status.to_s] || status.to_s
    end
  end
end
