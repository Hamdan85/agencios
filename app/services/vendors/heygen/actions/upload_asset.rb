# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Upload a source image (e.g. a UGC actor headshot, a product shot) to
      # HeyGen's asset store. `POST /v1/asset` → returns an `asset_id` you then
      # reference from CreatePhotoAvatar / template image variables.
      #
      # HeyGen's asset upload is a raw binary POST with the file's content-type
      # (NOT multipart/JSON), so this Action builds its own connection rather than
      # going through the JSON client. Inherits Vendors::Base for `credential`.
      # Returns the `asset_id`.
      #
      # See docs/integrations/heygen.md §4.
      class UploadAsset < Vendors::Base
        UPLOAD_URL = 'https://upload.heygen.com'

        def self.call(...) = new(...).call

        def initialize(io:, content_type:, api_key: nil)
          @io           = io
          @content_type = content_type
          @api_key      = api_key || credential(:heygen, :api_key, env: 'HEYGEN_API_KEY')
        end

        def call
          require_credential!(@api_key, 'heygen.api_key')

          conn = Faraday.new(url: UPLOAD_URL) do |f|
            f.response :json, content_type: /\bjson/
            f.adapter Faraday.default_adapter
          end

          response = conn.post('/v1/asset') do |req|
            req.headers['X-Api-Key']    = @api_key.to_s
            req.headers['Content-Type'] = @content_type
            req.body = @io.respond_to?(:read) ? @io.read : @io
          end

          unless response.success?
            raise Vendors::Heygen::Error.new('Asset upload failed', status: response.status, body: response.body)
          end

          body = response.body
          body.is_a?(Hash) ? body.dig('data', 'id') || body.dig('data', 'asset_id') : body
        end
      end
    end
  end
end
