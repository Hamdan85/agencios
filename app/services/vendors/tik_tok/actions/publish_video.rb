# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Direct Post a video via the Content Posting API (§6.1–6.2).
      #
      #   Vendors::TikTok::Actions::PublishVideo.call(
      #     social_account:, post_info:, video_url: "https://verified-domain/clip.mp4"
      #   )                                                   # PULL_FROM_URL
      #
      #   Vendors::TikTok::Actions::PublishVideo.call(
      #     social_account:, post_info:, video_bytes: <binary>
      #   )                                                   # FILE_UPLOAD
      #
      # Returns the `publish_id` (poll status via FetchPublishStatus). Raises on failure.
      class PublishVideo
        # Chunk sizing: ≥5 MB and ≤64 MB; final chunk may run up to 128 MB. We target
        # 10 MB chunks. Files < 5 MB must be sent whole (chunk_size = video_size).
        CHUNK_SIZE     = 10_000_000
        MIN_CHUNK      = 5_000_000
        MAX_FINAL_BYTE = 128_000_000

        def self.call(...) = new(...).call

        def initialize(social_account:, post_info:, video_url: nil, video_bytes: nil)
          @social_account = social_account
          @post_info = post_info
          @video_url = video_url
          @video_bytes = video_bytes
        end

        def call
          init = client.init_video(post_info: @post_info, source_info: source_info)
          data = init['data'] || {}
          publish_id = data['publish_id']
          upload_url = data['upload_url']

          # FILE_UPLOAD path: TikTok hands back an upload_url (valid 1h). PULL_FROM_URL
          # has no upload_url — TikTok downloads from video_url itself.
          transfer_chunks(upload_url) if upload_url

          publish_id
        end

        private

        def client
          @client ||= Vendors::TikTok::Client.new(access_token: @social_account.user_access_token)
        end

        def source_info
          return { source: 'PULL_FROM_URL', video_url: @video_url } if @video_url

          size = @video_bytes.bytesize
          if size < MIN_CHUNK
            # Whole-file upload: single chunk equal to the file size (HTTP 201 on PUT).
            { source: 'FILE_UPLOAD', video_size: size, chunk_size: size, total_chunk_count: 1 }
          else
            chunk = CHUNK_SIZE
            { source: 'FILE_UPLOAD', video_size: size, chunk_size: chunk,
              total_chunk_count: [size / chunk, 1].max }
          end
        end

        # Sequential PUTs with 0-indexed inclusive Content-Range (§6.2).
        def transfer_chunks(upload_url)
          size = @video_bytes.bytesize
          chunk = source_info[:chunk_size]
          total = source_info[:total_chunk_count]

          (0...total).each do |index|
            first = index * chunk
            # Final chunk swallows any remainder (may exceed chunk_size, up to 128 MB).
            last = index == total - 1 ? size - 1 : (first + chunk - 1)
            slice = @video_bytes.byteslice(first, last - first + 1)
            response = client.upload_chunk(
              upload_url: upload_url,
              bytes: slice,
              content_range: "bytes #{first}-#{last}/#{size}"
            )
            next if [200, 201, 206].include?(response.status)

            raise Vendors::Base::Error.new(
              "TikTok chunk upload failed (HTTP #{response.status})", status: response.status
            )
          end
        end
      end
    end
  end
end
