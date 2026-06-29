# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a multi-slide carousel creative. Produces a Creative (generated)
    # plus a billable `carousel` Generation on the active workspace.
    #
    # Real path: Prompts::CarouselCopy (brand identity + @handle + avatar + stock
    # imagery) drives per-slide copy; the image model renders each slide. Here we
    # stub the slide imagery via Vendors::ImageGen and synthesize headlines.
    class GenerateCarousel < Operations::Base
      PROVIDER = "image_gen"
      COST_CENTS = 30

      def initialize(ticket: nil, slides: 6, params: {})
        @ticket = ticket
        @slides = slides.to_i.clamp(3, 10)
        @params = params || {}
      end

      def call
        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: "carousel",
          source: :generated,
          status: :generating,
          provider: PROVIDER
        )

        slides = build_slides
        creative.update!(status: :ready, metadata: { slides: slides })

        generation = workspace.generations.create!(
          user: Current.user,
          creative: creative,
          kind: :carousel,
          status: :completed,
          provider: PROVIDER,
          cost_cents: COST_CENTS,
          params: @params,
          result: { slides: slides }
        )

        meter!(generation)
        broadcast(event: "generation_done", id: generation.id, kind: "carousel")
        generation
      end

      private

      # Carousel is a billable usage meter. Report it to Stripe Billing Meters
      # (idempotent on the generation id); a vendor/network hiccup must never fail
      # the user's generation, so swallow + log.
      def meter!(generation)
        Operations::Billing::RecordUsage.call(generation)
      rescue StandardError => e
        Rails.logger.warn("[GenerateCarousel] RecordUsage failed for generation #{generation.id}: #{e.message}")
      end

      def build_slides
        (1..@slides).map do |index|
          image = Vendors::ImageGen::Actions::GenerateImage.call(
            prompt: "Carousel slide #{index}",
            width: 1080,
            height: 1350
          )
          { index: index, image_url: image[:url], headline: "Slide #{index}" }
        end
      end

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
