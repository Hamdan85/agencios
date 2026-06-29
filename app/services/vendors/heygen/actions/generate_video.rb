# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Submit a talking-head avatar render. Async: HeyGen returns a `video_id`
      # immediately; the MP4 arrives via webhook (`avatar_video.success`) or is
      # picked up by `GetVideoStatus` polling.
      #
      # v3 (`POST /v3/videos`) is the primary path; v2 (`POST /v2/video/generate`,
      # `video_inputs`) is the fallback, supported through Oct 31 2026. Pass
      # `version: :v2` to force the legacy path. Returns the HeyGen `video_id`.
      #
      # See docs/integrations/heygen.md §3.
      class GenerateVideo
        def self.call(...) = new(...).call

        DEFAULT_BACKGROUND = { type: "color", value: "#FFFFFF" }.freeze

        def initialize(avatar:, voice:, script:, version: :v3,
                       title: nil, callback_id: nil, callback_url: nil,
                       aspect_ratio: "9:16", resolution: "1080p",
                       dimension: { width: 1080, height: 1920 },
                       avatar_style: "normal", background: DEFAULT_BACKGROUND,
                       caption: false, test: false, client: nil)
          # `avatar`/`voice` may be a bare id String or a Hash carrying ids +
          # per-render options (style, speed, voice_id), so the operation can pass
          # either a chosen id or a richer brief.
          @avatar_id    = extract_id(avatar)
          @voice_id     = extract_id(voice)
          @avatar       = avatar.is_a?(Hash) ? avatar.symbolize_keys : {}
          @voice        = voice.is_a?(Hash) ? voice.symbolize_keys : {}
          @script       = script.to_s
          @version      = version.to_sym
          @title        = title
          @callback_id  = callback_id
          @callback_url = callback_url
          @aspect_ratio = aspect_ratio
          @resolution   = resolution
          @dimension    = dimension
          @avatar_style = @avatar[:avatar_style] || avatar_style
          @background    = background
          @caption      = caption
          @test         = test
          @client       = client || Client.new
        end

        def call
          body = @version == :v2 ? handle_response(v2) : handle_response(v3)
          body.dig("data", "video_id")
        end

        private

        def handle_response(body)
          body
        end

        # v3 — flattened discriminated union keyed on `type`.
        def v3
          payload = {
            type: "avatar",
            avatar_id: @avatar_id,
            voice_id: @voice_id,
            script: @script,
            aspect_ratio: @aspect_ratio,
            resolution: @resolution,
            background: @background
          }
          payload[:title]        = @title if @title
          payload[:callback_id]  = @callback_id if @callback_id
          payload[:callback_url] = @callback_url if @callback_url
          payload[:caption]      = { file_format: "srt", style: "default" } if @caption
          @client.post("/v3/videos", payload)
        end

        # v2 — `video_inputs` scenes + `dimension`.
        def v2
          voice_input = { type: "text", input_text: @script, voice_id: @voice_id }
          voice_input[:speed] = @voice[:speed] if @voice[:speed]
          voice_input[:emotion] = @voice[:emotion] if @voice[:emotion]

          payload = {
            video_inputs: [{
              character: { type: "avatar", avatar_id: @avatar_id, avatar_style: @avatar_style },
              voice: voice_input,
              background: @background
            }],
            dimension: @dimension,
            caption: @caption,
            test: @test
          }
          payload[:title]        = @title if @title
          payload[:callback_id]  = @callback_id if @callback_id
          payload[:callback_url] = @callback_url if @callback_url
          @client.post("/v2/video/generate", payload)
        end

        def extract_id(value)
          return value if value.is_a?(String)

          if value.is_a?(Hash)
            v = value.symbolize_keys
            return v[:avatar_id] || v[:voice_id] || v[:id] || v[:talking_photo_id]
          end
          value
        end
      end
    end
  end
end
