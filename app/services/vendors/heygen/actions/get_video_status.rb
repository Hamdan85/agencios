# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Poll a render's status. Normalizes the v1/v2 envelope
      # (`GET /v1/video_status.get?video_id=`, body `{ code, data, message }`) and
      # the v3 envelope (`GET /v3/videos/{id}` → `VideoDetail`) into a uniform Hash:
      #
      #   { status:, video_url:, thumbnail_url:, gif_url:, duration:,
      #     failure_message:, raw: {...} }
      #
      # Status values: `pending` / `waiting` / `processing` / `completed` / `failed`.
      # `video_url` is presigned + time-limited — download promptly.
      #
      # See docs/integrations/heygen.md §3d.
      class GetVideoStatus
        def self.call(...) = new(...).call

        def initialize(video_id:, version: :v2, client: nil)
          @video_id = video_id
          @version  = version.to_sym
          @client   = client || Client.new
        end

        def call
          @version == :v3 ? from_v3 : from_v1
        end

        private

        # v1/v2: GET /v1/video_status.get?video_id=<id>
        def from_v1
          body = @client.get('/v1/video_status.get', video_id: @video_id)
          data = body['data'] || {}
          normalize(
            status: data['status'],
            video_url: data['video_url'],
            thumbnail_url: data['thumbnail_url'],
            gif_url: data['gif_url'],
            duration: data['duration'],
            failure_message: data.dig('error', 'message') || data['error'],
            raw: body
          )
        end

        # v3: GET /v3/videos/{video_id}
        def from_v3
          body = @client.get("/v3/videos/#{@video_id}")
          data = body['data'] || body
          normalize(
            status: data['status'],
            video_url: data['video_url'],
            thumbnail_url: data['thumbnail_url'],
            gif_url: data['gif_url'],
            duration: data['duration'],
            failure_message: data['failure_message'] || data['failure_code'],
            raw: body
          )
        end

        def normalize(status:, video_url:, thumbnail_url:, gif_url:, duration:, failure_message:, raw:)
          {
            status: status.to_s,
            completed: status.to_s == 'completed',
            failed: status.to_s == 'failed',
            video_url: video_url,
            thumbnail_url: thumbnail_url,
            gif_url: gif_url,
            duration: duration&.to_f,
            failure_message: failure_message,
            raw: raw
          }
        end
      end
    end
  end
end
