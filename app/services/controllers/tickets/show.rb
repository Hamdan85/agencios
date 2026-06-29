# frozen_string_literal: true

module Controllers
  module Tickets
    # The contextual ticket payload (ticket + subtasks + creatives + posts +
    # notes). Reused by Update/Advance to render the refreshed ticket.
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = find_ticket
        {
          ticket:      serialize(ticket, TicketSerializer),
          subtasks:    serialize_collection(ticket.subtasks.ordered, SubtaskSerializer),
          creatives:   serialize_collection(ticket.creatives, CreativeSerializer),
          attachments: serialize_collection(ticket.attachments.ordered, AttachmentSerializer),
          posts:       serialize_collection(ticket.posts, PostSerializer),
          notes:       serialize_collection(ticket.notes.chronological, NoteSerializer, member_names: member_names)
        }
      end

      private

      def find_ticket
        workspace.tickets.includes(
          :project, :assignee, :created_by, :subtasks, :creatives,
          attachments: { file_attachment: :blob },
          posts: :post_metrics,
          notes: [:user, { attachments: { file_attachment: :blob } }]
        ).find(@params[:id])
      end

      # { user_id => display_name } for resolving mention chips without N+1.
      def member_names
        workspace.memberships.includes(:user).to_h { |m| [m.user_id, m.user.display_name] }
      end
    end
  end
end
