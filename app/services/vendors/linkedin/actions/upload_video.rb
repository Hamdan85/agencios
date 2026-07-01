# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Videos API (replaces v2/assets). Multipart upload in 4 MB parts:
      #   1. POST /rest/videos?action=initializeUpload -> video urn + uploadInstructions
      #   2. PUT each 4 MB part to its uploadUrl (octet-stream); capture ETags in order
      #   3. POST /rest/videos?action=finalizeUpload with the ordered ETags
      # Returns the video URN to reference in content.media.id.
      # See docs/integrations/linkedin.md §6c.
      class UploadVideo
        def self.call(...) = new(...).call

        PART_SIZE = 4_194_304 # 4 MB - 1 byte boundary per the doc (lastByte 4194303)

        def initialize(social_account:, owner_urn:, bytes:)
          @social_account = social_account
          @owner_urn = owner_urn
          @bytes = bytes
        end

        # Returns "urn:li:video:...".
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)

          init = client.rest_post(
            '/rest/videos?action=initializeUpload',
            {
              'initializeUploadRequest' => {
                'owner' => @owner_urn,
                'fileSizeBytes' => @bytes.bytesize,
                'uploadCaptions' => false,
                'uploadThumbnail' => false
              }
            }
          )
          value = init.fetch('value')
          video_urn = value.fetch('video')
          upload_token = value['uploadToken'].to_s

          part_ids = upload_parts(client, value.fetch('uploadInstructions'))

          client.rest_post(
            '/rest/videos?action=finalizeUpload',
            {
              'finalizeUploadRequest' => {
                'video' => video_urn,
                'uploadToken' => upload_token,
                'uploadedPartIds' => part_ids
              }
            }
          )

          video_urn
        end

        private

        # PUT each part to its signed uploadUrl, slicing [firstByte..lastByte].
        # Returns the ETags in upload order.
        def upload_parts(client, instructions)
          Array(instructions).map do |part|
            first = part.fetch('firstByte')
            last  = part.fetch('lastByte')
            chunk = @bytes.byteslice(first, last - first + 1)
            client.upload_binary(part.fetch('uploadUrl'), chunk, content_type: 'application/octet-stream')
          end
        end
      end
    end
  end
end
