# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a single feed image via Google Banana (Imagen 3).
    # Produces a Creative (generated, ready) with the image attached to assets,
    # plus a tracked `image` Generation. Image generation is NOT metered via Stripe.
    class GenerateImage < Operations::Base
      PROVIDER = "google_banana"

      def initialize(ticket: nil, prompt:, ref_images: [], aspect_ratio: "1:1")
        @ticket       = ticket
        @prompt       = prompt
        @ref_images   = ref_images || []
        @aspect_ratio = aspect_ratio
      end

      def call
        creative = Operations::Creatives::Create.call(
          ticket:        @ticket,
          creative_type: "feed_image",
          source:        :generated,
          status:        :generating,
          provider:      PROVIDER,
          metadata:      { prompt: @prompt }
        )

        result = Vendors::Google::Banana::Actions::GenerateImage.call(
          prompt:       @prompt,
          aspect_ratio: @aspect_ratio
        )

        creative.assets.attach(
          io:           StringIO.new(result[:bytes]),
          filename:     "creative-#{creative.id}.jpg",
          content_type: result[:content_type]
        )
        creative.update!(status: :ready)

        generation = workspace.generations.create!(
          user:       Current.user,
          creative:   creative,
          kind:       :image,
          status:     :completed,
          provider:   PROVIDER,
          cost_cents: 0,
          params:     { prompt: @prompt, aspect_ratio: @aspect_ratio },
          result:     {}
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
