# frozen_string_literal: true

module Vendors
  module ImageGen
    module Actions
      # Preferred call site for generating a single image (SPECIFICATION.md §5).
      #
      # Accepts a `prompt`, optional brand `ref_images` (public URLs), and a
      # `size`. For backward compatibility it also accepts `width:`/`height:`
      # (existing carousel/image operations pass those) and folds them into `size`.
      #
      # Returns { url:, external_id: }.
      class GenerateImage
        def self.call(...) = new(...).call

        def initialize(prompt:, ref_images: [], size: nil, width: nil, height: nil)
          @prompt     = prompt
          @ref_images = ref_images || []
          @size       = size || (width && height ? "#{width}x#{height}" : "1080x1350")
        end

        def call
          Vendors::ImageGen::Client.new.generate_image(
            prompt: @prompt,
            ref_images: @ref_images,
            size: @size
          )
        end
      end
    end
  end
end
