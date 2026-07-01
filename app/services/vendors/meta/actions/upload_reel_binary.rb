# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB Reels — Step 2 UPLOAD binary to the rupload host (facebook.md §6e).
      # POST rupload.facebook.com/video-upload/{version}/{video_id}
      # Headers: Authorization: OAuth {token}, offset, file_size.
      # Pass raw `bytes`, OR omit the body and pass `file_url` (header) to have
      # Meta pull the file from a public URL.
      class UploadReelBinary
        def self.call(...) = new(...).call

        def initialize(social_account:, video_id:, bytes: nil, file_url: nil,
                       offset: 0, file_size: nil, client: nil)
          @social_account = social_account
          @video_id = video_id
          @bytes = bytes
          @file_url = file_url
          @offset = offset
          @file_size = file_size || bytes&.bytesize
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          headers = { 'offset' => @offset }
          headers['file_size'] = @file_size if @file_size
          headers['file_url'] = @file_url if @file_url

          @client.rupload(
            "video-upload/#{@client.graph_version}/#{@video_id}",
            body: @bytes,
            headers:
          )
        end
      end
    end
  end
end
