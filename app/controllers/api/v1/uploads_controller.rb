# frozen_string_literal: true

module Api
  module V1
    # Ad-hoc file uploads that aren't (yet) attached to a domain record — e.g.
    # the media references (photos / short guide videos) fed to the video
    # generator. Returns public URLs.
    class UploadsController < BaseController
      # POST /uploads/references — multipart files[] → [{ signed_id, url, kind }]
      def references = render_created(Controllers::Uploads::References.call(params:))
    end
  end
end
