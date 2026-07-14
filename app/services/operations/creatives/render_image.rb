# frozen_string_literal: true

module Operations
  module Creatives
    # The SLOW half of an image generation — runs in Creatives::RenderImageJob,
    # never in-request. Re-derives the reference images from the stored context,
    # calls the vendor, attaches the result and finalizes the records. Results
    # reach the UI via Action Cable (`generation_done` / `creative_ready`); any
    # failure fails the generation and refunds the credits (FailGeneration).
    class RenderImage < Operations::Base
      PROVIDER = AiUsageLog::PROVIDER_OPENROUTER

      def initialize(generation:)
        @generation = generation
        @creative   = generation.creative
        @params     = (generation.params || {}).with_indifferent_access
      end

      def call
        ticket = @creative.ticket
        ctx = ::Tickets::CreativeContext.for(
          ticket,
          creative_type: @params[:creative_type],
          client: resolve_client,
          overrides: { revision_notes: @params[:revision_notes] }
        )

        result = Vendors::OpenRouter::Actions::GenerateImage.call(
          prompt: @params[:prompt],
          aspect_ratio: @params[:aspect_ratio],
          reference_images: ctx.reference_images
        )

        @creative.assets.attach(
          io: StringIO.new(result[:bytes]),
          filename: "creative-#{@creative.id}.jpg",
          content_type: result[:content_type]
        )
        @creative.update!(status: :ready)
        @generation.update!(status: :completed)

        log_ai_cost(cost_cents: result[:cost_cents], model: result[:model])
        Broadcaster.generations(@generation.workspace_id, 'generation_done', id: @generation.id, kind: 'image')
        Broadcaster.ticket(ticket, 'creative_ready', creative_id: @creative.id) if ticket
        # The RELIABLE autopilot seam — broadcasts are fire-and-forget.
        Operations::Autopilot::OnGenerationSettled.call(generation: @generation)
        @generation
      rescue StandardError => e
        Operations::Creatives::FailGeneration.call(generation: @generation, reason: e.message)
        raise
      end

      private

      def resolve_client
        id = @params[:client_id]
        return nil if id.blank?

        workspace.clients.find_by(id: id)
      end

      # OpenRouter reports the REAL USD cost per generation (usage.cost) — pass it
      # through as cost_cents so the ledger stores it verbatim (no price table).
      def log_ai_cost(cost_cents: nil, model: nil)
        Operations::Ai::LogUsage.call(
          provider: PROVIDER,
          operation: 'generate_image',
          model: model.presence || Vendors::OpenRouter::Image::DEFAULT_MODEL,
          units: 1,
          unit_kind: AiUsageLog::UNIT_IMAGE,
          cost_cents: cost_cents,
          subject: @generation
        )
      end
    end
  end
end
