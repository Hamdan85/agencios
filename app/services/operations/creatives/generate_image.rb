# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a single image via Google Banana (Imagen 3), folding the ticket
    # scope + brand identity into the prompt and the creative type's spec into the
    # aspect ratio. Produces a Creative (generated, ready) plus a tracked `image`
    # Generation. Image is NOT Stripe-metered, but its vendor cost is recorded in
    # the AI ledger (AiUsageLog) via Operations::Ai::LogUsage.
    class GenerateImage < Operations::Base
      PROVIDER = 'google_banana'

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
        refs   = ctx.reference_images
        prompt = ctx.image_prompt(@prompt)
        # Brand logo + creator avatar ride along as OPTIONAL references — the model
        # decides, per the prompt, whether to actually use them.
        prompt = "#{prompt}. #{::Tickets::CreativeContext::REFERENCE_ASSETS_DIRECTIVE}" if refs.any?

        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: ctx.creative_type || type,
          source: :generated,
          status: :generating,
          provider: PROVIDER,
          metadata: { prompt: prompt, aspect_ratio: aspect }
        )

        generation = workspace.generations.create!(
          user: Current.user,
          creative: creative,
          kind: :image,
          status: :processing,
          provider: PROVIDER,
          cost_cents: 0, # not Stripe-metered; real vendor cost is in AiUsageLog
          params: { prompt: prompt, aspect_ratio: aspect },
          result: {}
        )

        # Charge prepaid credits BEFORE spending vendor $ — raises
        # InsufficientCredits (→ 402) if the wallet can't cover it.
        Operations::Credits::Debit.call(
          workspace: workspace,
          amount: Pricing.credits_for(kind: :image),
          generation: generation
        )

        begin
          result = Vendors::Google::Banana::Actions::GenerateImage.call(
            prompt: prompt,
            aspect_ratio: aspect,
            reference_images: refs
          )
        rescue StandardError
          Operations::Credits::Refund.call(generation: generation)
          generation.update!(status: :failed)
          creative.update!(status: :failed)
          raise
        end

        creative.assets.attach(
          io: StringIO.new(result[:bytes]),
          filename: "creative-#{creative.id}.jpg",
          content_type: result[:content_type]
        )
        creative.update!(status: :ready)
        generation.update!(status: :completed)

        log_ai_cost(generation)
        broadcast(event: 'generation_done', id: generation.id, kind: 'image')
        generation
      end

      private

      def type
        @creative_type.presence || @ticket&.creative_type.presence || 'feed_image'
      end

      def resolve_client
        return nil if @client_id.blank?

        workspace.clients.find_by(id: @client_id)
      end

      def log_ai_cost(generation)
        Operations::Ai::LogUsage.call(
          provider: AiUsageLog::PROVIDER_GOOGLE_BANANA,
          operation: 'generate_image',
          model: 'imagen',
          units: 1,
          unit_kind: AiUsageLog::UNIT_IMAGE,
          subject: generation
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
