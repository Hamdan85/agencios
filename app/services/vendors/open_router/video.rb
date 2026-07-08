# frozen_string_literal: true

require 'open-uri'

module Vendors
  module OpenRouter
    # OpenRouter VIDEO-generation client (https://openrouter.ai/api/v1/videos).
    # Separate from the chat `Client` (different endpoint + async job lifecycle):
    # video is submit → poll. One API reaches every video model (Veo 3.1, Seedance,
    # Kling, …) by slug, so the platform swaps engines per mode via VideoConfig
    # without changing this class.
    #
    # Image inputs (both optional, per the OpenRouter video API):
    #   * frame_images    — first/last-frame conditioning ([{ url:, frame_type: }])
    #   * input_references — reference-to-video (subject/product consistency)
    #
    # Mirrors Vendors::Base error handling. The api_key is an app-level secret in
    # credentials (openrouter.api_key), ENV fallback for local dev.
    class Video < Vendors::Base
      BASE_URL = 'https://openrouter.ai'

      def initialize(api_key: nil)
        @api_key = api_key || credential(:openrouter, :api_key, env: 'OPENROUTER_API_KEY')
      end

      # Kick off a render. Returns the job id (String). Raises on error / missing key.
      #   model:            OpenRouter video slug (resolved by VideoConfig)
      #   prompt:           the scene/script prompt
      #   aspect_ratio:     '9:16' | '1:1' | '16:9' | '4:5'
      #   duration:         seconds (nil ⇒ model default)
      #   frame_images:     [{ url:, frame_type: 'first' | 'last' }]
      #   input_references: [{ url: }]  (product/subject reference photos)
      #   generate_audio:   output toggle — whether the MODEL authors its own
      #                     audio (dialogue/SFX/music). We set false whenever we
      #                     dub a fixed Cartesia voice in post (so the model never
      #                     adds a competing voice/soundtrack under our track), and
      #                     true only when we rely on the model's native audio.
      # NOTE: OpenRouter's video API takes NO driving-audio INPUT — references are
      # hard-typed to image_url and only `generate_audio` (an OUTPUT boolean) is
      # honored. `audio_references` are therefore NOT sent (the engine would ignore
      # them); a fixed voice is delivered by dubbing in compose, not by the model.
      def submit(model:, prompt:, aspect_ratio: nil, duration: nil, frame_images: [],
                 input_references: [], audio_references: [], generate_audio: nil)
        require_credential!(@api_key, 'openrouter.api_key')

        payload = { model: model, prompt: prompt.to_s }
        payload[:aspect_ratio] = aspect_ratio if aspect_ratio.present?
        payload[:duration_seconds] = duration.to_i if duration.present?
        payload[:generate_audio] = generate_audio unless generate_audio.nil?
        payload[:frame_images] = Array(frame_images).map { |f| frame_part(f) } if frame_images.present?
        refs = Array(input_references).map { |ref| reference_part(ref) }
        payload[:input_references] = refs if refs.present?

        body = handle(connection.post('/api/v1/videos') { |req| req.body = payload })
        job_id = body.is_a?(Hash) ? (body['id'] || body.dig('data', 'id')) : nil
        raise Error.new('OpenRouter video submit returned no job id', body: body) if job_id.blank?

        job_id.to_s
      end

      # Poll a job. Normalizes OpenRouter's payload into the shape the finalize
      # path consumes:
      #   { status:, completed:, failed:, video_url:, thumbnail_url:, duration:,
      #     cost_cents:, failure_message:, raw: }
      def status(job_id:)
        require_credential!(@api_key, 'openrouter.api_key')

        body = handle(connection.get("/api/v1/videos/#{job_id}"))
        normalize_status(body)
      end

      # Download a completed asset to an IO. OpenRouter's `unsigned_urls` are
      # served by its API and require the bearer token — a bare fetch 401s. Any
      # redirect OpenRouter issues to the underlying (already-signed) storage is
      # followed by open-uri without re-sending the header.
      def download(url)
        require_credential!(@api_key, 'openrouter.api_key')

        URI.parse(url.to_s).open('Authorization' => "Bearer #{@api_key}")
      end

      private

      # A frame-conditioning input: the same image_url content-part shape PLUS a
      # frame_type of 'first_frame' | 'last_frame'. Callers pass { url:, frame_type: }
      # with 'first'/'last' (or the full suffixed form) — normalized here.
      def frame_part(frame)
        h = (frame.respond_to?(:to_h) ? frame.to_h : {}).symbolize_keys
        ft = h[:frame_type].to_s
        ft = "#{ft}_frame" unless ft.end_with?('_frame')
        url = h[:url] || h.dig(:image_url, :url)
        { type: 'image_url', image_url: { url: url }, frame_type: ft }
      end

      # A reference input is a discriminated union keyed by `type` — the same
      # content-part shape the chat API uses: { type: 'image_url', image_url: { url: } }.
      # Callers pass a plain { url: } (product/subject photos ⇒ image) or may set
      # :type explicitly ('image_url' | 'audio_url' | 'video_url').
      def reference_part(ref)
        h    = (ref.respond_to?(:to_h) ? ref.to_h : {}).symbolize_keys
        type = h[:type].presence&.to_s || 'image_url'
        url  = h[:url] || h.dig(type.to_sym, :url) || h.dig(:image_url, :url)
        { type: type, type.to_sym => { url: url } }
      end

      def normalize_status(body)
        b = body.is_a?(Hash) ? body : {}
        state = (b['status'] || b.dig('data', 'status')).to_s.downcase
        {
          status: state,
          completed: state == 'completed' || state == 'succeeded',
          failed: state == 'failed' || state == 'error' || state == 'canceled',
          video_url: video_url(b),
          thumbnail_url: b['thumbnail_url'] || b.dig('data', 'thumbnail_url'),
          duration: (b['duration_seconds'] || b['duration'] || b.dig('data', 'duration_seconds')),
          cost_cents: usage_cost_cents(b),
          failure_message: b['error'].is_a?(Hash) ? b.dig('error', 'message') : b['error'],
          raw: b
        }
      end

      # OpenRouter returns the finished asset under `unsigned_urls` (or a single
      # `url`); tolerate either shape and nesting under `data`.
      def video_url(b)
        urls = b['unsigned_urls'] || b.dig('data', 'unsigned_urls')
        return urls.first if urls.is_a?(Array) && urls.any?

        b['url'] || b.dig('data', 'url') || b.dig('output', 'url')
      end

      # Real generation cost in cents when OpenRouter reports usage.cost (USD).
      def usage_cost_cents(b)
        cost = b.dig('usage', 'cost') || b.dig('data', 'usage', 'cost')
        cost.present? ? (cost.to_f * 100.0) : nil
      end

      def connection
        @connection ||= build_connection(BASE_URL, headers: default_headers).tap do |conn|
          conn.options.timeout = 60
          conn.options.open_timeout = 10
        end
      end

      def default_headers
        {
          'Authorization' => "Bearer #{@api_key}",
          'HTTP-Referer' => SystemConfig.app_host,
          'X-Title' => 'agencios'
        }
      end
    end
  end
end
