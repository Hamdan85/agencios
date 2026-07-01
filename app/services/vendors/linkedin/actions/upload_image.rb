# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Images API (replaces v2/assets registerUpload):
      #   1. POST /rest/images?action=initializeUpload  -> { uploadUrl, image (urn) }
      #   2. PUT  {uploadUrl} with raw image bytes       (signed dms-uploads URL)
      # Returns the image URN to reference in content.media.id.
      # See docs/integrations/linkedin.md §6b.
      class UploadImage
        def self.call(...) = new(...).call

        def initialize(social_account:, owner_urn:, bytes:, content_type: 'image/jpeg')
          @social_account = social_account
          @owner_urn = owner_urn
          @bytes = bytes
          @content_type = content_type
        end

        # Returns "urn:li:image:...".
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)

          init = client.rest_post(
            '/rest/images?action=initializeUpload',
            { 'initializeUploadRequest' => { 'owner' => @owner_urn } }
          )
          value = init.fetch('value')
          image_urn = value.fetch('image')

          client.upload_binary(value.fetch('uploadUrl'), @bytes, content_type: @content_type)

          image_urn
        end
      end
    end
  end
end
