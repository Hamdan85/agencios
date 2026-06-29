# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a single feed image. Produces a Creative (generated, ready) plus
    # an `image` Generation. Image generation is tracked but NOT metered.
    class GenerateImage < Operations::Base
      PROVIDER = "image_gen"

      def initialize(ticket: nil, prompt:, ref_images: [])
        @ticket = ticket
        @prompt = prompt
        @ref_images = ref_images || []
      end

      def call
        image = Vendors::ImageGen::Actions::GenerateImage.call(
          prompt: @prompt,
          width: 1080,
          height: 1350,
          ref_images: @ref_images
        )

        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: "feed_image",
          source: :generated,
          status: :ready,
          provider: PROVIDER,
          metadata: { image_url: image[:url], prompt: @prompt }
        )

        generation = workspace.generations.create!(
          user: Current.user,
          creative: creative,
          kind: :image,
          status: :completed,
          provider: PROVIDER,
          external_id: image[:external_id],
          cost_cents: 0,
          params: { prompt: @prompt, ref_images: @ref_images },
          result: { image_url: image[:url] }
        )

        broadcast(event: "generation_done", id: generation.id, kind: "image")
        generation
      end

      private

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
