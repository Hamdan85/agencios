# frozen_string_literal: true

module Operations
  module Tickets
    # Plain attribute update (NOT status — that only goes through ChangeStatus).
    class Update < Operations::Base
      def initialize(ticket:, params:)
        @ticket = ticket
        @params = params
      end

      def call
        attrs = @params.slice(:title, :assignee_id, :priority, :project_id, :due_date,
                              :scheduled_at, :creative_type).to_h.symbolize_keys
        attrs[:channels] = Array(@params[:channels]).compact_blank if @params.key?(:channels)

        previous_assignee_id = @ticket.assignee_id
        @ticket.update!(attrs)
        # Posting-time edits (drawer meta, calendar drag) must reach the
        # still-scheduled posts — the publish sweep reads Post#scheduled_at.
        Operations::Posts::Reschedule.call(ticket: @ticket, scheduled_at: attrs[:scheduled_at]) if attrs[:scheduled_at].present?
        Broadcaster.board(@ticket.workspace_id, 'ticket_updated', ticket_id: @ticket.id)
        notify_reassignment(previous_assignee_id)
        @ticket
      end

      # Notify the new assignee when assignment actually changed (skip the actor
      # assigning a ticket to themselves).
      def notify_reassignment(previous_assignee_id)
        return if @ticket.assignee_id.blank? || @ticket.assignee_id == previous_assignee_id

        Operations::Push::Notify.call(
          user: @ticket.assignee, actor: Current.user,
          title: 'Ticket atribuído a você',
          body: @ticket.title,
          path: "/tickets/#{@ticket.id}"
        )
      end
    end
  end
end
