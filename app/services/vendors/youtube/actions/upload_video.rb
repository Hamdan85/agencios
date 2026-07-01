# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uploads a video via the resumable upload protocol (§6.2-6.4) and returns the
      # new video id. Quota: videos.insert ≈ 100 units (dropped from ~1600 on
      # 2025-12-04; default daily quota is 10,000 units, ~100 uploads/day).
      #
      #   Vendors::Youtube::Actions::UploadVideo.call(
      #     social_account:, bytes: <binary>, metadata: { snippet:, status: },
      #     content_type: "video/*", chunk_size: nil, notify_subscribers: true
      #   )
      #
      # Shorts: there is no Shorts API field — upload a vertical 9:16, ≤3-min file and
      # add "#Shorts" to the title/description (the caller builds metadata accordingly);
      # YouTube auto-classifies it into the Shorts feed (§6.5).
      class UploadVideo
        # Chunk size must be a multiple of 256 KB (262144 bytes), except the last chunk.
        CHUNK_UNIT = 262_144
        # Whole-file upload below this; chunk above it for resilience.
        WHOLE_FILE_LIMIT = 64 * CHUNK_UNIT # 16 MB

        def self.call(...) = new(...).call

        def initialize(social_account:, bytes:, metadata:, content_type: 'video/*',
                       chunk_size: nil, notify_subscribers: true)
          @social_account = social_account
          @bytes = bytes
          @metadata = metadata
          @content_type = content_type
          @chunk_size = chunk_size
          @notify_subscribers = notify_subscribers
        end

        def call
          session_uri = client.init_resumable_upload(
            metadata: @metadata,
            total_size: @bytes.bytesize,
            content_type: @content_type,
            notify_subscribers: @notify_subscribers
          )
          raise Vendors::Base::Error, 'YouTube did not return a resumable session URI' if session_uri.blank?

          video = chunked? ? upload_chunked(session_uri) : upload_whole(session_uri)
          video['id'] || raise(Vendors::Base::Error, 'YouTube upload returned no video id')
        end

        private

        def client
          @client ||= Vendors::Youtube::Client.new(access_token: @social_account.user_access_token)
        end

        def chunked?
          @chunk_size.present? || @bytes.bytesize > WHOLE_FILE_LIMIT
        end

        # §6.3 whole-file PUT → 201 Created with the full video resource.
        def upload_whole(session_uri)
          response = client.upload_bytes(
            session_uri: session_uri, bytes: @bytes, content_type: @content_type
          )
          finalize!(response)
        end

        # §6.3 chunked: each non-final chunk a multiple of 256 KB, contiguous.
        # Non-final → 308 Resume Incomplete; final → 201 Created with the resource.
        def upload_chunked(session_uri)
          size = @bytes.bytesize
          chunk = normalized_chunk_size
          offset = 0
          last_response = nil

          while offset < size
            last = [offset + chunk, size].min - 1
            slice = @bytes.byteslice(offset, last - offset + 1)
            last_response = client.upload_bytes(
              session_uri: session_uri,
              bytes: slice,
              content_range: "bytes #{offset}-#{last}/#{size}",
              content_type: @content_type
            )
            # 308 Resume Incomplete is expected for non-final chunks.
            unless [200, 201, 308].include?(last_response.status)
              raise Vendors::Base::Error.new(
                "YouTube chunk upload failed (HTTP #{last_response.status})", status: last_response.status
              )
            end
            offset = last + 1
          end

          finalize!(last_response)
        end

        def normalized_chunk_size
          base = @chunk_size || WHOLE_FILE_LIMIT
          # Round down to a 256 KB multiple (required for non-final chunks).
          [(base / CHUNK_UNIT) * CHUNK_UNIT, CHUNK_UNIT].max
        end

        def finalize!(response)
          unless response.status == 201
            raise Vendors::Base::Error.new(
              "YouTube upload did not complete (HTTP #{response.status})", status: response.status
            )
          end
          parse_body(response.body)
        end

        def parse_body(body)
          return body if body.is_a?(Hash)

          JSON.parse(body.to_s)
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
