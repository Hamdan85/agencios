# frozen_string_literal: true

module Api
  module V1
    # Ad-hoc file uploads that aren't (yet) attached to a domain record — e.g. the
    # product reference photos fed to the video generator. Returns public URLs.
    class UploadsController < BaseController
      # POST /uploads/reference_images — multipart files[] → [{ signed_id, url }]
      def reference_images = render_created(Controllers::Uploads::ReferenceImages.call(params:))
    end
  end
end
