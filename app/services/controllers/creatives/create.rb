# frozen_string_literal: true

module Controllers
  module Creatives
    # Upload a creative (source: uploaded) and attach its asset files.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        creative_type = @params.require(:creative_type)
        # Only accept files compatible with the creative type's media (an image
        # can't be a reel; a video can't be a feed image). Validate BEFORE creating
        # the record so a rejected upload leaves nothing behind.
        validate_media!(creative_type, @params[:assets])

        creative = Operations::Creatives::Create.call(
          ticket: ticket,
          creative_type: creative_type,
          source: :uploaded,
          # An upload IS the finished deliverable — ready from the start, so it
          # shows up in Aprovação/Postagem like a generated piece does.
          status: :ready,
          caption: @params[:caption],
          metadata: @params[:metadata]&.permit!.to_h
        )
        attach_assets(creative)
        { creative: serialize(creative, CreativeSerializer) }
      end

      private

      def attach_assets(creative)
        files = @params[:assets]
        return if files.blank?

        creative.assets.attach(files)
      end

      def validate_media!(creative_type, files)
        allowed = ::Creatives.accepted_upload_media(creative_type)
        Array(files).each do |file|
          next unless file.respond_to?(:content_type)

          kind = file.content_type.to_s.split('/').first
          next if allowed.include?(kind)

          raise Operations::Errors::Invalid, I18n.t("api.creatives.#{media_mismatch_key(allowed)}")
        end
      end

      def media_mismatch_key(allowed)
        return 'media_mismatch_images_or_videos' if allowed.sort == %w[image video]

        allowed.include?('video') ? 'media_mismatch_videos' : 'media_mismatch_images'
      end
    end
  end
end
