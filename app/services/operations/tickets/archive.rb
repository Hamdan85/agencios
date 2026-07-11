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

        # Archiving shelves the ticket — nothing of it should still go live. The
        # publish sweep reads Post#scheduled_at with no archived filter, so the
        # pending schedules must be CANCELED here or the archived ticket would
        # keep publishing on time. Restoring does not resurrect them; the user
        # re-schedules from the posting step.
        canceled = @archived ? cancel_pending_posts : 0

        @ticket.update!(archived_at: @archived ? Time.current : nil)

        key, params = archive_note(canceled)
        Operations::Notes::Create.call(
          ticket: @ticket, user: nil, kind: :system,
          i18n_key: key, i18n_params: params
        )

        Broadcaster.ticket(@ticket, @archived ? 'archived' : 'unarchived')
        Broadcaster.board(@ticket.workspace_id, 'card_archived',
                          ticket_id: @ticket.id, archived: @archived)
        @ticket
      end

      private

      # Cancel through the posts' own operation (the single cancel authority),
      # never a bare destroy — same path the posting step's cancel action uses.
      def cancel_pending_posts
        @ticket.posts.status_scheduled.to_a.each do |post|
          Operations::Posts::Cancel.call(post: post)
        end.size
      end

      # Returns [i18n_key, params] for the history note (rendered per reader).
      def archive_note(canceled)
        return ['notes.archive.restored', {}] unless @archived
        return ['notes.archive.archived', {}] if canceled.zero?

        ['notes.archive.archived_with_canceled', { count: canceled }]
      end
    end
  end
end
