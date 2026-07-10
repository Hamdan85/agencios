# frozen_string_literal: true

module Vendors
  module OpenRouter
    module Actions
      # Generates a single image via OpenRouter (Gemini "nano banana" by default).
      #
      # Accepts a `prompt` and an `aspect_ratio` (or `width`/`height` for
      # backwards-compatible callers — converted to the nearest ratio).
      #
      # Returns { bytes: <binary>, content_type:, cost_cents: }.
      # The caller attaches the bytes to ActiveStorage.
      class GenerateImage
        def self.call(...) = new(...).call

        RATIO_MAP = {
          [1, 1] => '1:1',
          [16, 9] => '16:9',
          [9, 16] => '9:16',
          [4, 3] => '4:3',
          [3, 4] => '3:4'
        }.freeze

        def initialize(prompt:, aspect_ratio: nil, width: nil, height: nil, negative_prompt: nil,
                       reference_images: [])
          @prompt            = prompt
          @negative_prompt   = negative_prompt
          @reference_images  = reference_images || []
          @aspect_ratio      = aspect_ratio.presence ||
                               derive_ratio(width.to_i, height.to_i) ||
                               '1:1'
        end

        def call
          Vendors::OpenRouter::Image.new.generate_image(
            prompt: @prompt,
            aspect_ratio: @aspect_ratio,
            negative_prompt: @negative_prompt,
            reference_images: @reference_images
          )
        end

        private

        def derive_ratio(width, height)
          return nil if width.zero? || height.zero?

          gcd = width.gcd(height)
          RATIO_MAP[[width / gcd, height / gcd]]
        end
      end
    end
  end
end
