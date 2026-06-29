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

        raise Operations::Errors::InvalidTransition, "Apenas gestores podem retroceder um ticket."
      end

      def apply_status!(_from_status)
        attrs = { status: @to_status }
        attrs[:position] = @position if @position
        attrs[:published_at] = Time.current if @to_status == "published" && @ticket.published_at.nil?
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

      def enqueue_summary
        SummarizeTicketJob.perform_later(@ticket.id, @to_status)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] could not enqueue summary: #{e.message}")
      end

      def fire_side_effects(_from_status)
        case @to_status
        when "scheduled"     then ensure_posts_for_channels
        when "published"     then publish_scheduled_posts
        when "retrospective" then draft_retrospective
        when "done"          then spawn_follow_ups
        end
      end

      # On completion, if the retrospective recommends iterating/repeating, spawn a
      # pre-filled ideation ticket linked back to this one (iteration/repetition of).
      def spawn_follow_ups
        rec = @ticket.fields_for("retrospective")["repeat_recommendation"].to_s
        return unless %w[iterate repeat].include?(rec)

        Operations::Tickets::SpawnFollowUp.call(source: @ticket, recommendation: rec, user: @user)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] spawn_follow_ups failed: #{e.message}")
      end

      def ensure_posts_for_channels
        # Validate channels + scheduled_at, then ensure a Post per channel.
        return if @ticket.channels.blank?

        client = @ticket.project.client
        @ticket.channels.each do |channel|
          account = client.social_accounts.find_by(provider: channel)
          next unless account

          @ticket.posts.find_or_create_by!(social_account_id: account.id) do |post|
            post.workspace_id = @ticket.workspace_id
            post.status = :scheduled
            post.scheduled_at = @ticket.scheduled_at
            post.caption = @ticket.fields_for("production")["caption"]
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] ensure_posts failed: #{e.message}")
      end

      def publish_scheduled_posts
        @ticket.posts.status_scheduled.find_each do |post|
          PublishPostJob.perform_later(post.id)
        rescue StandardError => e
          Rails.logger.warn("[ChangeStatus] enqueue publish failed: #{e.message}")
        end
      end

      def draft_retrospective
        DraftRetrospectiveJob.perform_later(@ticket.id)
      rescue StandardError => e
        Rails.logger.warn("[ChangeStatus] enqueue retro failed: #{e.message}")
      end

      def broadcast(from_status)
        Broadcaster.ticket(@ticket, "status_changed", to: @to_status, from: from_status)
        Broadcaster.board(@ticket.workspace_id, "card_moved",
                          ticket_id: @ticket.id, to: @to_status, from: from_status, position: @ticket.position)
      end

      def step(status) = WORKFLOW.index(status.to_sym) || 0
      def label(status) = Ticket::STATUS_LABELS[status.to_s] || status.to_s
    end
  end
end
