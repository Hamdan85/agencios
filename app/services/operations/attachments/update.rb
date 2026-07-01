# frozen_string_literal: true

module Operations
  module Attachments
    # Updates an attachment's metadata (title/description/position). The blob
    # itself is immutable — re-uploading is a new Attachment.
    class Update < Operations::Base
      ALLOWED = %i[title description position].freeze

      def initialize(attachment:, attributes:)
        @attachment = attachment
        @attributes = (attributes || {}).symbolize_keys.slice(*ALLOWED)
      end

      def call
        @attachment.update!(@attributes)
        Broadcaster.ticket(@attachment.ticket, 'attachment_updated', attachment_id: @attachment.id)
        @attachment
      end
    end
  end
end
