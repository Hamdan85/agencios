# frozen_string_literal: true

module Controllers
  module Uploads
    # POST /uploads/references — multipart `files[]`. Stores each media file
    # (image or video) as an ActiveStorage blob and returns public URLs the
    # generation vendor (OpenRouter) can fetch. Media reference files feed the
    # video generator: product photos, character/style images, and camera/motion
    # reference videos (Operations::Video::References types them by role at
    # attach time). Guests cannot upload.
    class References < Base
      MAX_FILES = 3
      ACCEPTED_IMAGES = %w[image/jpeg image/png image/webp].freeze
      ACCEPTED_VIDEOS = %w[video/mp4 video/quicktime video/webm].freeze
      # Reference videos are short guides (camera/motion), not footage.
      MAX_VIDEO_BYTES = 50.megabytes

      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        files = Array(@params[:files]).compact.first(MAX_FILES)
        raise Operations::Errors::Invalid, 'Envie ao menos um arquivo.' if files.empty?

        { references: files.map { |f| store(f) } }
      end

      private

      def store(file)
        validate!(file)
        blob = ActiveStorage::Blob.create_and_upload!(
          io: file.tempfile, filename: file.original_filename, content_type: file.content_type
        )
        kind = ACCEPTED_VIDEOS.include?(file.content_type.to_s) ? 'vid' : 'img'
        { signed_id: blob.signed_id, url: public_url(blob), kind: kind }
      end

      def validate!(file)
        ct = file.respond_to?(:content_type) ? file.content_type.to_s : ''
        if ACCEPTED_VIDEOS.include?(ct)
          return if file.size.to_i <= MAX_VIDEO_BYTES

          raise Operations::Errors::Invalid, 'Vídeo de referência muito grande (máx. 50 MB).'
        end
        return if ACCEPTED_IMAGES.include?(ct)

        raise Operations::Errors::Invalid,
              'Formato não suportado. Envie JPG, PNG, WEBP ou um vídeo MP4/MOV/WEBM.'
      end

      # A public URL served by the app (redirects to S3 in prod) so the async
      # render vendor can fetch the reference during the (minutes-long) job.
      def public_url(blob)
        Rails.application.routes.url_helpers.rails_blob_url(blob, host: SystemConfig.app_host)
      end
    end
  end
end
