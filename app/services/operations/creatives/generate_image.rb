# frozen_string_literal: true

module Operations
  module Creatives
    # Generates a single image via OpenRouter (Gemini image model), folding the
    # ticket scope + brand identity into the prompt and the creative type's spec
    # into the aspect ratio. Produces a Creative (generated, ready) plus a tracked
    # `image` Generation. Image is NOT Stripe-metered, but its vendor cost is
    # recorded in the AI ledger (AiUsageLog) via Operations::Ai::LogUsage.
    class GenerateImage < Operations::Base
      PROVIDER = AiUsageLog::PROVIDER_OPENROUTER

      def initialize(ticket: nil, prompt: nil, ref_images: [], aspect_ratio: nil, creative_type: nil,
                     client_id: nil, revision_notes: nil)
        @ticket         = ticket
        @prompt         = prompt
        @ref_images     = ref_images || []
        @aspect_ratio   = aspect_ratio
        @creative_type  = creative_type
        @client_id      = client_id
        @revision_notes = revision_notes
      end

      def call
        ctx    = ::Tickets::CreativeContext.for(@ticket, creative_type: type, client: resolve_client,
                                                         overrides: { revision_notes: @revision_notes })
        ensure_client_active!(ctx.client)
        aspect = @aspect_ratio.presence || ctx.image_aspect_ratio
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

        # Surface the "Gerando…" card immediately (the studio/board gallery is
        # subscribed to this channel) even though the vendor work below runs
        # inline — the broadcast is out-of-band from the blocking HTTP request.
        broadcast(event: 'generation_progress', id: generation.id, kind: 'image', status: 'processing')

        # Everything that can fail — the credit debit, the vendor call, the attach —
        # is wrapped so ANY error moves the records to `failed` and refunds credits
        # (FailGeneration), never leaving the creative stranded in `generating`.
        begin
          # Charge prepaid credits BEFORE spending vendor $ — raises
          # InsufficientCredits (→ 402) if the wallet can't cover it.
          Operations::Credits::Debit.call(
            workspace: workspace,
            amount: Pricing.credits_for(kind: :image),
            generation: generation
          )

          result = Vendors::OpenRouter::Actions::GenerateImage.call(
            prompt: prompt,
            aspect_ratio: aspect,
            reference_images: refs
          )

          creative.assets.attach(
            io: StringIO.new(result[:bytes]),
            filename: "creative-#{creative.id}.jpg",
            content_type: result[:content_type]
          )
          creative.update!(status: :ready)
          generation.update!(status: :completed)
        rescue StandardError => e
          Operations::Creatives::FailGeneration.call(generation: generation, reason: e.message)
          raise
        end

        log_ai_cost(generation, cost_cents: result[:cost_cents], model: result[:model])
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

      # OpenRouter reports the REAL USD cost per generation (usage.cost) — pass it
      # through as cost_cents so the ledger stores it verbatim (no price table).
      def log_ai_cost(generation, cost_cents: nil, model: nil)
        Operations::Ai::LogUsage.call(
          provider: PROVIDER,
          operation: 'generate_image',
          model: model.presence || Vendors::OpenRouter::Image::DEFAULT_MODEL,
          units: 1,
          unit_kind: AiUsageLog::UNIT_IMAGE,
          cost_cents: cost_cents,
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
