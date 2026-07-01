# frozen_string_literal: true

module Operations
  module Attachments
    # Attaches one uploaded file to a ticket as an Attachment, appends it to the
    # end of the ticket's file list, and broadcasts the change. When created
    # inside a comment, `note:` links it (it still belongs to the ticket, so it
    # appears in the file list) and `broadcast: false` lets the caller emit a
    # single `note_added` event instead of one `attachment_added` per file.
    class Create < Operations::Base
      def initialize(ticket:, file:, uploaded_by: nil, title: nil, description: nil, metadata: {}, note: nil,
                     broadcast: true)
        @ticket = ticket
        @file = file
        @uploaded_by = uploaded_by
        @title = title
        @description = description
        @metadata = metadata || {}
        @note = note
        @broadcast = broadcast
      end

      def call
        attachment = @ticket.attachments.new(
          workspace_id: @ticket.workspace_id,
          uploaded_by: @uploaded_by,
          note: @note,
          title: @title.presence,
          description: @description.presence,
          position: next_position,
          metadata: @metadata
        )
        attachment.file.attach(@file)
        attachment.save!

        Broadcaster.ticket(@ticket, 'attachment_added', attachment_id: attachment.id) if @broadcast
        attachment
      end

      private

      def next_position
        (@ticket.attachments.maximum(:position) || -1) + 1
      end
    end
  end
end
