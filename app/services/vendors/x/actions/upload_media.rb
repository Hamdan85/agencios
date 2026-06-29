# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # v2 chunked media upload (replaces v1.1 media/upload):
      #   INIT -> APPEND (per chunk) -> FINALIZE -> STATUS (poll if processing_info)
      # Returns the final media_id once succeeded.
      # Needs `media.write`. See docs/integrations/x-twitter.md §6a.
      class UploadMedia
        def self.call(...) = new(...).call

        CHUNK_SIZE     = 1_048_576 # ~1 MB segments (keep < 5 MB per the doc)
        STATUS_POLLS   = 60
        DEFAULT_WAIT   = 2 # seconds; overridden by check_after_secs when present

        # media_category: tweet_image | tweet_gif | tweet_video | amplify_video
        def initialize(social_account:, bytes:, media_type:, media_category:)
          @social_account = social_account
          @bytes = bytes
          @media_type = media_type
          @media_category = media_category
        end

        # Returns the media_id (String).
        def call
          client = Vendors::X::Client.new(social_account: @social_account)

          init = client.media_command(
            command: "INIT",
            media_type: @media_type,
            total_bytes: @bytes.bytesize,
            media_category: @media_category
          )
          media_id = media_id_from(init)

          append_chunks(client, media_id)

          final = client.media_command(command: "FINALIZE", media_id: media_id)
          wait_until_succeeded(client, media_id, final)

          media_id
        end

        private

        def append_chunks(client, media_id)
          segment = 0
          offset = 0
          total = @bytes.bytesize
          while offset < total
            chunk = @bytes.byteslice(offset, CHUNK_SIZE)
            client.media_append(media_id: media_id, segment_index: segment, chunk: chunk)
            offset += chunk.bytesize
            segment += 1
          end
        end

        # Videos/GIFs carry a processing_info block — poll STATUS until succeeded.
        # Images finalize immediately (no processing_info).
        def wait_until_succeeded(client, media_id, final_body)
          info = processing_info(final_body)
          return if info.nil?

          STATUS_POLLS.times do
            state = info["state"]
            return if state == "succeeded"
            raise Vendors::Base::Error, "X media processing failed" if state == "failed"

            sleep(info["check_after_secs"] || DEFAULT_WAIT)
            status = client.media_status(media_id)
            info = processing_info(status) || {}
          end
        end

        # The v2 media endpoint nests the payload under "data".
        def media_id_from(body)
          (body["data"] || body)["media_id_string"] ||
            (body["data"] || body)["id"] ||
            (body["data"] || body)["media_id"].to_s
        end

        def processing_info(body)
          (body["data"] || body)["processing_info"]
        end
      end
    end
  end
end
