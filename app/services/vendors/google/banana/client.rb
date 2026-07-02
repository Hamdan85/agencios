# frozen_string_literal: true

require 'base64'

module Vendors
  module Google
    module Banana
      # Google AI image generation client — Gemini image model via the Google AI API.
      #
      # Endpoint: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
      # Auth:     API key in query param (?key=...) — issued from https://aistudio.google.com/apikey
      #
      # NOTE: `:predict` is Vertex AI only. The generativelanguage.googleapis.com API
      # (AI Studio keys) uses `:generateContent` with responseModalities: ["IMAGE"].
      #
      # Credentials: `google_banana.api_key` / ENV GOOGLE_BANANA_API_KEY
      #              `google_banana.model`   / ENV GOOGLE_BANANA_MODEL
      #
      # The API returns base64-encoded image bytes inline in the response.
      # The caller is responsible for attaching the bytes to ActiveStorage.
      class Client < Vendors::Base
        BASE_URL      = 'https://generativelanguage.googleapis.com'
        DEFAULT_MODEL = 'gemini-2.0-flash-preview-image-generation'

        SUPPORTED_ASPECT_RATIOS = %w[1:1 16:9 9:16 4:3 3:4].freeze

        # Inline image MIME types the Gemini generateContent API accepts. Anything
        # else (notably image/svg+xml brand logos) is rejected by the API with an
        # "Unsupported MIME type" 400 — such references are dropped before sending.
        SUPPORTED_IMAGE_MIME_TYPES = %w[
          image/png image/jpeg image/webp image/heic image/heif
        ].freeze

        def initialize(api_key: nil, model: nil)
          @api_key = api_key ||
                     credential(:google_banana, :api_key, env: 'GOOGLE_BANANA_API_KEY')
          @model   = model ||
                     credential(:google_banana, :model, env: 'GOOGLE_BANANA_MODEL').presence ||
                     DEFAULT_MODEL
        end

        # Generates one image. Returns { bytes: <binary String>, content_type: "image/jpeg" }.
        #
        # `reference_images` — optional labeled visual references (brand logo,
        # creator avatar, …) handed to the multimodal model. Each is a hash
        # `{ label:, bytes:, content_type: }`; the label text precedes its inline
        # image so the model knows what it is and can decide whether to use it.
        def generate_image(prompt:, aspect_ratio: '1:1', negative_prompt: nil, reference_images: [])
          require_credential!(@api_key, 'google_banana.api_key')

          payload = {
            contents: [
              {
                parts: [{ text: full_prompt(prompt, aspect_ratio, negative_prompt) }] +
                       reference_parts(reference_images)
              }
            ],
            generationConfig: {
              responseModalities: %w[IMAGE TEXT]
            }
          }

          result  = handle(connection.post("/v1beta/models/#{@model}:generateContent?key=#{@api_key}", payload))
          parts   = result.dig('candidates', 0, 'content', 'parts') || []
          image   = parts.find { |p| p['inlineData'] }

          raise Vendors::Google::Banana::Error, 'No image returned by Google Banana' unless image

          {
            bytes: Base64.strict_decode64(image['inlineData']['data']),
            content_type: image['inlineData']['mimeType'].presence || 'image/jpeg'
          }
        end

        private

        def connection
          @connection ||= build_connection(BASE_URL)
        end

        # Turn labeled reference images into interleaved [text, inlineData] parts.
        # A label part precedes each image so the model can tell them apart.
        def reference_parts(reference_images)
          Array(reference_images).flat_map do |ref|
            bytes = ref && ref[:bytes]
            next [] if bytes.blank?

            mime = ref[:content_type].presence || 'image/png'
            unless SUPPORTED_IMAGE_MIME_TYPES.include?(mime.to_s.downcase)
              Rails.logger.warn(
                "[Google::Banana] skipping reference image with unsupported MIME type: #{mime}"
              )
              next []
            end

            parts = []
            parts << { text: "Referência — #{ref[:label]}:" } if ref[:label].present?
            parts << {
              inlineData: {
                mimeType: mime,
                data: Base64.strict_encode64(bytes)
              }
            }
            parts
          end
        end

        # Fold aspect ratio and negative prompt into the text prompt — the
        # generateContent API doesn't have dedicated params for these.
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
end
