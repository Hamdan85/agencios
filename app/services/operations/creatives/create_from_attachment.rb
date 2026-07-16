# frozen_string_literal: true

module Operations
  module Creatives
    # Turns a file already uploaded to the ticket (Attachment) into a Creative
    # of the given type — the same deliverable an upload would produce, without
    # re-uploading: the creative's asset shares the attachment's blob (purging
    # either side is a no-op while the other still references it).
    #
    # Only media the type accepts qualifies (Creatives.accepted_upload_media —
    # an image can't become a reel), so this is the single guard for every
    # caller, mirroring the upload path's controller-side validation.
    class CreateFromAttachment < Operations::Base
      def initialize(ticket:, attachment:, creative_type:, caption: nil)
        @ticket = ticket
        @attachment = attachment
        @creative_type = creative_type.to_s
        @caption = caption
      end

      def call
        validate_media!

        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: @creative_type,
          source: :uploaded,
          status: :ready,
          caption: @caption,
          metadata: { 'attachment_id' => @attachment.id }
        )
        creative.assets.attach(@attachment.file.blob)
        creative
      end

      private

      def validate_media!
        allowed = ::Creatives.accepted_upload_media(@creative_type)
        return if allowed.include?(@attachment.kind)

        raise Operations::Errors::Invalid, I18n.t("api.creatives.#{media_mismatch_key(allowed)}")
      end

      def media_mismatch_key(allowed)
        return 'media_mismatch_images_or_videos' if allowed.sort == %w[image video]

        allowed.include?('video') ? 'media_mismatch_videos' : 'media_mismatch_images'
      end
    end
  end
end
