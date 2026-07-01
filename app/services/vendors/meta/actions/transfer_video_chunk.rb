# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB video Resumable Upload — Phase 2 TRANSFER. POST /{page_id}/videos with
      # upload_phase=transfer + start_offset + video_file_chunk (multipart),
      # looped until start_offset == end_offset (facebook.md §6d). Returns
      # { start_offset, end_offset } for the next chunk.
      #
      # NOTE: video_file_chunk is a multipart file part; when wiring live, send it
      # as a Faraday::Multipart::FilePart. Here we pass the raw chunk through the
      # form encoder so the request shape is faithful.
      class TransferVideoChunk
        def self.call(...) = new(...).call

        def initialize(social_account:, upload_session_id:, start_offset:, video_file_chunk:, client: nil)
          @social_account = social_account
          @upload_session_id = upload_session_id
          @start_offset = start_offset
          @video_file_chunk = video_file_chunk
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.post(
            "/#{@social_account.page_id}/videos",
            params: {
              upload_phase: 'transfer',
              upload_session_id: @upload_session_id,
              start_offset: @start_offset,
              video_file_chunk: @video_file_chunk
            }
          )
        end
      end
    end
  end
end
