# frozen_string_literal: true

require 'base64'

module Vendors
  module OpenRouter
    # OpenRouter IMAGE-generation client (https://openrouter.ai/api/v1/chat/completions).
    # Image models (Gemini "nano banana", etc.) are reached through the SAME
    # OpenAI-compatible chat endpoint as text — the image comes back inline on
    # `choices[0].message.images[]` as data URIs when `modalities` asks for it.
    #
    # Separate from the chat `Client` (which is specialized for text/tool/stream)
    # and the `Video` client (async submit→poll), mirroring how those are split.
    #
    # Endpoint: POST /api/v1/chat/completions with `modalities: ["image","text"]`.
    # Auth:     Authorization: Bearer <key> (openrouter.api_key / OPENROUTER_API_KEY).
    #
    # Returns { bytes: <binary String>, content_type:, cost_cents: } — the caller
    # attaches the bytes to ActiveStorage. Raises on error (so the operation can
    # refund credits), like the Banana client it replaces.
    class Image < Vendors::Base
      BASE_URL      = 'https://openrouter.ai'
      # Google's Gemini image model ("nano banana") via OpenRouter. Override with
      # `openrouter.image_model` / OPENROUTER_IMAGE_MODEL.
      DEFAULT_MODEL = 'google/gemini-2.5-flash-image'

      # Aspect ratios we fold into the prompt (the chat API has no dedicated param).
      SUPPORTED_ASPECT_RATIOS = %w[1:1 16:9 9:16 4:3 3:4].freeze

      # Raster MIME types accepted as inline reference-image input. Anything else
      # (notably image/svg+xml brand logos) is dropped before sending.
      SUPPORTED_IMAGE_MIME_TYPES = %w[
        image/png image/jpeg image/webp image/heic image/heif
      ].freeze

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || credential(:openrouter, :api_key, env: 'OPENROUTER_API_KEY')
        @model   = model.presence ||
                   credential(:openrouter, :image_model, env: 'OPENROUTER_IMAGE_MODEL').presence ||
                   DEFAULT_MODEL
      end

      # Generates one image. Returns { bytes:, content_type:, cost_cents: }.
      #
      # `reference_images` — optional labeled visual references (brand logo,
      # creator avatar, …) handed to the multimodal model. Each is a hash
      # `{ label:, bytes:, content_type: }`; the label text precedes its inline
      # image so the model knows what it is and can decide whether to use it.
      def generate_image(prompt:, aspect_ratio: '1:1', negative_prompt: nil, reference_images: [])
        require_credential!(@api_key, 'openrouter.api_key')

        content = [{ type: 'text', text: full_prompt(prompt, aspect_ratio, negative_prompt) }] +
                  reference_parts(reference_images)

        payload = {
          model: @model,
          messages: [{ role: 'user', content: content }],
          modalities: %w[image text],
          usage: { include: true }
        }

        body  = handle(connection.post('/api/v1/chat/completions') { |req| req.body = payload })
        image = extract_image(body)

        raise Vendors::OpenRouter::Error, 'No image returned by OpenRouter' unless image

        image.merge(cost_cents: cost_cents(body))
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

      # Pull the first inline image off the assistant message and decode its data
      # URI into { bytes:, content_type: }. Returns nil when none is present.
      def extract_image(body)
        images = body.is_a?(Hash) ? body.dig('choices', 0, 'message', 'images') : nil
        return nil unless images.is_a?(Array)

        url = images.filter_map { |img| img.is_a?(Hash) ? img.dig('image_url', 'url') : nil }.first
        decode_data_uri(url)
      end

      # data:image/png;base64,<...> → { bytes: <binary>, content_type: 'image/png' }.
      def decode_data_uri(url)
        return nil if url.blank?

        match = %r{\Adata:(?<mime>[^;,]+)?(?<base64>;base64)?,(?<data>.*)\z}m.match(url.to_s)
        return nil unless match

        data = match[:data].to_s
        bytes = match[:base64] ? Base64.strict_decode64(data) : CGI.unescape(data)
        { bytes: bytes, content_type: match[:mime].presence || 'image/png' }
      rescue ArgumentError
        nil
      end

      # Real generation cost in cents when OpenRouter reports usage.cost (USD).
      def cost_cents(body)
        cost = body.is_a?(Hash) ? body.dig('usage', 'cost') : nil
        cost.present? ? (cost.to_f * 100.0) : nil
      end

      # Turn labeled reference images into interleaved [text, image_url] content
      # parts. A label part precedes each image so the model can tell them apart.
      def reference_parts(reference_images)
        Array(reference_images).flat_map do |ref|
          bytes = ref && ref[:bytes]
          next [] if bytes.blank?

          mime = ref[:content_type].presence || 'image/png'
          unless SUPPORTED_IMAGE_MIME_TYPES.include?(mime.to_s.downcase)
            Rails.logger.warn(
              "[Vendors::OpenRouter::Image] skipping reference image with unsupported MIME type: #{mime}"
            )
            next []
          end

          parts = []
          parts << { type: 'text', text: "Referência — #{ref[:label]}:" } if ref[:label].present?
          parts << {
            type: 'image_url',
            image_url: { url: "data:#{mime};base64,#{Base64.strict_encode64(bytes)}" }
          }
          parts
        end
      end

      # Fold aspect ratio and negative prompt into the text prompt — the chat
      # completions API has no dedicated params for these.
      def full_prompt(prompt, aspect_ratio, negative_prompt)
        parts = [prompt]
        parts << "Aspect ratio: #{normalize_aspect_ratio(aspect_ratio)}." if aspect_ratio.present?
        parts << "Avoid: #{negative_prompt}." if negative_prompt.present?
        parts.join(' ')
      end

      def normalize_aspect_ratio(ratio)
        SUPPORTED_ASPECT_RATIOS.include?(ratio.to_s) ? ratio.to_s : '1:1'
      end
    end
  end
end
