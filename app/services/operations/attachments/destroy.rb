# frozen_string_literal: true

module Operations
  module Attachments
    # Removes an attachment (purging its blob) and broadcasts the change.
    class Destroy < Operations::Base
      def initialize(attachment:)
        @attachment = attachment
      end

      def call
        ticket = @attachment.ticket
        attachment_id = @attachment.id
        @attachment.destroy!

        Broadcaster.ticket(ticket, 'attachment_removed', attachment_id: attachment_id)
        true
      end
    end
  end
end
