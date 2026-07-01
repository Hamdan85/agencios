# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG Reels resumable upload (Mode B) — PUT raw bytes to the rupload host
      # for a container created with upload_type=resumable (instagram.md §6c).
      # POST rupload.facebook.com/ig-api-upload/{version}/{creation_id}
      # Headers: Authorization: OAuth {token}, offset, file_size.
      class UploadResumableVideo
        def self.call(...) = new(...).call

        # `bytes` is the raw video binary; file_size defaults to its bytesize.
        def initialize(social_account:, creation_id:, bytes:, offset: 0, file_size: nil, client: nil)
          @social_account = social_account
          @creation_id = creation_id
          @bytes = bytes
          @offset = offset
          @file_size = file_size || bytes&.bytesize
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.rupload(
            "ig-api-upload/#{@client.graph_version}/#{@creation_id}",
            body: @bytes,
            headers: { 'offset' => @offset, 'file_size' => @file_size }
          )
        end
      end
    end
  end
end
