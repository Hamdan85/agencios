# frozen_string_literal: true

module Controllers
  module Uploads
    # POST /uploads/reference_images — multipart `files[]`. Stores each image as an
    # ActiveStorage blob and returns a public URL the generation vendor (OpenRouter)
    # can fetch. Used by the video generator's Product mode (reference photos) and
    # any generator that takes reference images. Guests cannot upload.
    class ReferenceImages < Base
      MAX_FILES = 3
      ACCEPTED = %w[image/jpeg image/png image/webp].freeze

      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        files = Array(@params[:files]).compact.first(MAX_FILES)
        raise Operations::Errors::Invalid, 'Envie ao menos uma imagem.' if files.empty?

        { reference_images: files.map { |f| store(f) } }
      end

      private

      def store(file)
        validate!(file)
        blob = ActiveStorage::Blob.create_and_upload!(
          io: file.tempfile, filename: file.original_filename, content_type: file.content_type
        )
        { signed_id: blob.signed_id, url: public_url(blob) }
      end

      def validate!(file)
        ct = file.respond_to?(:content_type) ? file.content_type.to_s : ''
        return if ACCEPTED.include?(ct)

        raise Operations::Errors::Invalid, 'Formato não suportado. Envie JPG, PNG ou WEBP.'
      end

      # A public URL served by the app (redirects to S3 in prod) so the async
      # render vendor can fetch the reference during the (minutes-long) job.
      def public_url(blob)
        Rails.application.routes.url_helpers.rails_blob_url(blob, host: SystemConfig.app_host)
      end
    end
  end
end
