# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a multi-slide carousel creative via Google Banana (Imagen 3).
    # Produces a Creative (generated, ready) plus a billable `carousel` Generation.
    class GenerateCarousel < Operations::Base
      PROVIDER   = "google_banana"
      COST_CENTS = 30

      def initialize(ticket: nil, slides: 6, params: {})
        @ticket = ticket
        @slides = slides.to_i.clamp(3, 10)
        @params = params || {}
      end

      def call
        creative = Operations::Creatives::Create.call(
          ticket:        @ticket,
          creative_type: "carousel",
          source:        :generated,
          status:        :generating,
          provider:      PROVIDER
        )

        slides = build_slides(creative)
        creative.update!(status: :ready, metadata: { slides: slides })

        generation = workspace.generations.create!(
          user:       Current.user,
          creative:   creative,
          kind:       :carousel,
          status:     :completed,
          provider:   PROVIDER,
          cost_cents: COST_CENTS,
          params:     @params,
          result:     { slides: slides }
        )

        meter!(generation)
        broadcast(event: "generation_done", id: generation.id, kind: "carousel")
        generation
      end

      private

      def build_slides(creative)
        (1..@slides).map do |index|
          result = Vendors::Google::Banana::Actions::GenerateImage.call(
            prompt:       slide_prompt(index),
            aspect_ratio: "1:1"
          )

          blob = creative.assets.attach(
            io:           StringIO.new(result[:bytes]),
            filename:     "slide-#{index}.jpg",
            content_type: result[:content_type]
          )

          { index: index, headline: "Slide #{index}" }
        end
      end

      def slide_prompt(index)
        base = @params[:prompt].presence || "Carousel slide"
        "#{base} — slide #{index} of #{@slides}"
      end

      # Carousel is a billable usage meter. Swallow errors so a Stripe hiccup
      # never fails the user's generation.
      def meter!(generation)
        Operations::Billing::RecordUsage.call(generation)
      rescue StandardError => e
        Rails.logger.warn("[GenerateCarousel] RecordUsage failed for generation #{generation.id}: #{e.message}")
      end

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
