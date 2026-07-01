# frozen_string_literal: true

module Operations
  module Tickets
    # Archive (or restore) a single ticket by toggling `archived_at`. Archived
    # tickets drop off the board (which is scoped to `.active`) but remain visible
    # in the global list under the "archived" view. Writes a history note and
    # broadcasts so any open board / ticket view refreshes.
    class Archive < Operations::Base
      def initialize(ticket, user:, archived: true)
        @ticket = ticket
        @user = user
        @archived = archived
      end

      def call
        return @ticket if @ticket.archived? == @archived

        @ticket.update!(archived_at: @archived ? Time.current : nil)

        Operations::Notes::Create.call(
          ticket: @ticket, user: nil, kind: :system,
          body: @archived ? 'Ticket arquivado.' : 'Ticket restaurado.'
        )

        Broadcaster.ticket(@ticket, @archived ? 'archived' : 'unarchived')
        Broadcaster.board(@ticket.workspace_id, 'card_archived',
                          ticket_id: @ticket.id, archived: @archived)
        @ticket
      end
    end
  end
end
