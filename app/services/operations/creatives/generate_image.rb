# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a single image via Google Banana (Imagen 3), folding the ticket
    # scope + brand identity into the prompt and the creative type's spec into the
    # aspect ratio. Produces a Creative (generated, ready) plus a tracked `image`
    # Generation. Image is NOT Stripe-metered, but its vendor cost is recorded in
    # the AI ledger (AiUsageLog) via Operations::Ai::LogUsage.
    class GenerateImage < Operations::Base
      PROVIDER = "google_banana"

      def initialize(ticket: nil, prompt: nil, ref_images: [], aspect_ratio: nil, creative_type: nil, client_id: nil)
        @ticket        = ticket
        @prompt        = prompt
        @ref_images    = ref_images || []
        @aspect_ratio  = aspect_ratio
        @creative_type = creative_type
        @client_id     = client_id
      end

      def call
        ctx    = ::Tickets::CreativeContext.for(@ticket, creative_type: type, client: resolve_client)
        aspect = @aspect_ratio.presence || ctx.banana_aspect_ratio
        prompt = ctx.image_prompt(@prompt)

        creative = Operations::Creatives::Create.call(
          ticket:        @ticket,
          creative_type: ctx.creative_type || type,
          source:        :generated,
          status:        :generating,
          provider:      PROVIDER,
          metadata:      { prompt: prompt, aspect_ratio: aspect }
        )

        result = Vendors::Google::Banana::Actions::GenerateImage.call(
          prompt:       prompt,
          aspect_ratio: aspect
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
          cost_cents: 0, # not Stripe-metered; real vendor cost is in AiUsageLog
          params:     { prompt: prompt, aspect_ratio: aspect },
          result:     {}
        )

        log_ai_cost(generation)
        broadcast(event: "generation_done", id: generation.id, kind: "image")
        generation
      end

      private

      def type
        @creative_type.presence || @ticket&.creative_type.presence || "feed_image"
      end

      def resolve_client
        return nil if @client_id.blank?

        workspace.clients.find_by(id: @client_id)
      end

      def log_ai_cost(generation)
        Operations::Ai::LogUsage.call(
          provider:  AiUsageLog::PROVIDER_GOOGLE_BANANA,
          operation: "generate_image",
          model:     "imagen",
          units:     1,
          unit_kind: AiUsageLog::UNIT_IMAGE,
          subject:   generation
        )
      end

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
