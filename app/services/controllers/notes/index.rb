# frozen_string_literal: true

module Controllers
  module Notes
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        notes = ticket.notes.chronological.includes(:user, attachments: { file_attachment: :blob })
        { notes: serialize_collection(notes, NoteSerializer, member_names: member_names) }
      end

      private

      # { user_id => display_name } for resolving mention chips without N+1.
      def member_names
        workspace.memberships.includes(:user).to_h { |m| [m.user_id, m.user.display_name] }
      end
    end
  end
end
