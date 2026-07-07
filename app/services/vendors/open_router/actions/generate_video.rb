# frozen_string_literal: true

module Vendors
  module OpenRouter
    module Actions
      # Submit a video render to OpenRouter and return the job id. The MODEL is
      # resolved from VideoConfig by generation mode (avatar/product) — the caller
      # never picks an engine (platform decides best cost/benefit).
      class GenerateVideo
        def self.call(...) = new(...).call

        def initialize(mode:, prompt:, aspect_ratio: nil, duration: nil,
                       frame_images: [], input_references: [], audio_references: [], model: nil)
          @mode             = mode.to_s
          @prompt           = prompt
          @aspect_ratio     = aspect_ratio
          @duration         = duration
          @frame_images     = frame_images || []
          @input_references = input_references || []
          @audio_references = audio_references || []
          @model            = model
        end

        def call
          Vendors::OpenRouter::Video.new.submit(
            model: @model.presence || VideoConfig.instance.model_for(@mode),
            prompt: @prompt,
            aspect_ratio: @aspect_ratio,
            duration: @duration,
            frame_images: @frame_images,
            input_references: @input_references,
            audio_references: @audio_references
          )
        end
      end
    end
  end
end
