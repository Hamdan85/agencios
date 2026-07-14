# frozen_string_literal: true

require 'base64'

module Vendors
  module OpenRouter
    # OpenRouter IMAGE-generation client, on the DEDICATED images API
    # (https://openrouter.ai/docs/features/multimodal/image-generation) — the
    # catalog at GET /api/v1/images/models (Gemini, FLUX, GPT-image, Recraft, …),
    # NOT the chat-completions modality trick this client used before. That
    # unlocks image-only engines (e.g. black-forest-labs/flux.2-pro) that have
    # no chat endpoint at all.
    #
    # Separate from the chat `Client` (text/tool/stream) and the `Video` client
    # (async submit→poll), mirroring how those are split.
    #
    # Endpoint: POST /api/v1/images — `model`, `prompt`, `aspect_ratio`, and
    #           labeled references via `input_references` (data URLs). Engines
    #           that don't support a param have it dropped by the router, so the
    #           aspect ratio is ALSO folded into the prompt as a fallback.
    # Auth:     Authorization: Bearer <key> (openrouter.api_key / OPENROUTER_API_KEY).
    #
    # Returns { bytes: <binary String>, content_type:, cost_cents:, model: } —
    # the caller attaches the bytes to ActiveStorage and logs the model that
    # actually rendered (the slug is admin-editable, so no caller may assume the
    # coded default). Raises on error (so the operation can refund credits).
    class Image < Vendors::Base
      BASE_URL      = 'https://openrouter.ai'
      # Google's Gemini image model ("nano banana"). This is only the coded
      # seed — the live slug is admin-editable in ImageConfig; the
      # `openrouter.image_model` credential / OPENROUTER_IMAGE_MODEL env var
      # remains as a fallback between the two.
      DEFAULT_MODEL = 'google/gemini-2.5-flash-image'

      # The ratios our creative specs use — a subset every mainstream engine's
      # `aspect_ratio` enum covers. Anything else falls back to square.
      SUPPORTED_ASPECT_RATIOS = %w[1:1 16:9 9:16 4:3 3:4].freeze

      # Raster MIME types accepted as inline reference-image input. Anything else
      # (notably image/svg+xml brand logos) is dropped before sending.
      SUPPORTED_IMAGE_MIME_TYPES = %w[
        image/png image/jpeg image/webp image/heic image/heif
      ].freeze

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || credential(:openrouter, :api_key, env: 'OPENROUTER_API_KEY')
        @model   = model.presence ||
                   ImageConfig.instance.model ||
                   credential(:openrouter, :image_model, env: 'OPENROUTER_IMAGE_MODEL').presence ||
                   DEFAULT_MODEL
      end

      # Generates one image. Returns { bytes:, content_type:, cost_cents:, model: }.
      #
      # `reference_images` — optional labeled visual references (brand logo,
      # creator avatar, …) handed to the engine. Each is a hash
      # `{ label:, bytes:, content_type: }`; the images go in `input_references`
      # (in order) and their labels are folded into the prompt as a numbered
      # legend so the model knows what each one is.
      def generate_image(prompt:, aspect_ratio: '1:1', negative_prompt: nil, reference_images: [])
        require_credential!(@api_key, 'openrouter.api_key')

        refs = usable_references(reference_images)
        payload = {
          model: @model,
          prompt: full_prompt(prompt, aspect_ratio, negative_prompt, refs),
          aspect_ratio: normalize_aspect_ratio(aspect_ratio),
          n: 1
        }
        payload[:input_references] = refs.map { |ref| reference_entry(ref) } if refs.any?

        body  = handle(connection.post('/api/v1/images') { |req| req.body = payload })
        image = extract_image(body)

        raise Vendors::OpenRouter::Error, 'No image returned by OpenRouter' unless image

        image.merge(cost_cents: cost_cents(body), model: @model)
      end

      private

      def connection
        @connection ||= build_connection(BASE_URL, headers: default_headers).tap do |conn|
          # Image generations run well past the 30s default.
          conn.options.timeout = 180
          conn.options.open_timeout = 10
        end
      end

      def default_headers
        {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json',
          'HTTP-Referer' => SystemConfig.app_host,
          'X-Title' => 'agencios'
        }
      end

      # The generated image lives at data[0] as base64 + media type.
      def extract_image(body)
        entry = body.is_a?(Hash) ? Array(body['data']).first : nil
        return nil unless entry.is_a?(Hash) && entry['b64_json'].present?

        {
          bytes: Base64.strict_decode64(entry['b64_json']),
          content_type: entry['media_type'].presence || 'image/png'
        }
      rescue ArgumentError
        nil
      end

      # Real generation cost in cents when OpenRouter reports usage.cost (USD).
      def cost_cents(body)
        cost = body.is_a?(Hash) ? body.dig('usage', 'cost') : nil
        cost.present? ? (cost.to_f * 100.0) : nil
      end

      # References the engine can actually take: non-blank bytes, raster MIME.
      def usable_references(reference_images)
        Array(reference_images).select do |ref|
          next false if ref.nil? || ref[:bytes].blank?

          mime = (ref[:content_type].presence || 'image/png').to_s.downcase
          next true if SUPPORTED_IMAGE_MIME_TYPES.include?(mime)

          Rails.logger.warn(
            "[Vendors::OpenRouter::Image] skipping reference image with unsupported MIME type: #{mime}"
          )
          false
        end
      end

      def reference_entry(ref)
        mime = ref[:content_type].presence || 'image/png'
        { type: 'image_url', image_url: { url: "data:#{mime};base64,#{Base64.strict_encode64(ref[:bytes])}" } }
      end

      # Fold the aspect ratio (fallback for engines without the param), the
      # negative prompt (no engine param exists) and the reference legend into
      # the text prompt.
      def full_prompt(prompt, aspect_ratio, negative_prompt, refs)
        parts = [prompt]
        parts << "Aspect ratio: #{normalize_aspect_ratio(aspect_ratio)}." if aspect_ratio.present?
        parts << "Avoid: #{negative_prompt}." if negative_prompt.present?

        legend = refs.each_with_index.filter_map do |ref, i|
          "#{i + 1}. #{ref[:label]}" if ref[:label].present?
        end
        parts << "Reference images, in order: #{legend.join('; ')}." if legend.any?

        parts.join(' ')
      end

      def normalize_aspect_ratio(ratio)
        SUPPORTED_ASPECT_RATIOS.include?(ratio.to_s) ? ratio.to_s : '1:1'
      end
    end
  end
end
