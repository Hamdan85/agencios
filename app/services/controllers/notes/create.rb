# frozen_string_literal: true

module Controllers
  module Notes
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        attrs = note_params
        note = Operations::Notes::Create.call(
          ticket: ticket,
          user: user,
          kind: :comment,
          body: attrs[:body],
          mentioned_user_ids: Array(attrs[:mentioned_user_ids]),
          files: Array(attrs[:files]).compact_blank
        )
        { note: serialize(note, NoteSerializer) }
      end

      private

      def note_params
        @params.require(:note).permit(:body, mentioned_user_ids: [], files: [])
      end
    end
  end
end
