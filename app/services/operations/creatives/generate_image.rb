# frozen_string_literal: true

module Operations
  module Creatives
    # Starts a single-image generation. This is the FAST, in-request half (the
    # project rule for ALL generation kinds): it folds the ticket scope + brand
    # identity into the prompt, creates the Creative (generating) + the tracked
    # `image` Generation, charges prepaid credits (raises InsufficientCredits →
    # 402 before any vendor spend) and hands off to Creatives::RenderImageJob.
    # The vendor render NEVER runs in-request — the UI gets the processing
    # generation back immediately and receives the result via Action Cable
    # (`generation_done` on generations_<workspace_id>, `creative_ready` on
    # ticket_<id>).
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
        prompt = ctx.image_prompt(@prompt)
        # Brand logo + creator avatar ride along as OPTIONAL references — the model
        # decides, per the prompt, whether to actually use them. The reference
        # BYTES are re-derived by the render half; here they only shape the prompt.
        prompt = "#{prompt}. #{::Tickets::CreativeContext::REFERENCE_ASSETS_DIRECTIVE}" if ctx.reference_images.any?

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
          cost_cents: 0, # real vendor cost is recorded in AiUsageLog by the render half
          # Everything the render job needs to re-derive the context off-request.
          params: { prompt: prompt, aspect_ratio: aspect, creative_type: type,
                    client_id: @client_id, revision_notes: @revision_notes }.compact,
          result: {}
        )

        # Surface the "Gerando…" card immediately — the gallery/board are
        # subscribed to this channel.
        Broadcaster.generations(workspace.id, 'generation_progress',
                                id: generation.id, kind: 'image', status: 'processing')

        # Charge prepaid credits BEFORE any vendor spend — raises
        # InsufficientCredits (→ 402) and fails/refunds the records if the wallet
        # can't cover it.
        begin
          Operations::Credits::Debit.call(
            workspace: workspace,
            amount: Pricing.credits_for(kind: :image),
            generation: generation
          )
        rescue StandardError => e
          Operations::Creatives::FailGeneration.call(generation: generation, reason: e.message)
          raise
        end

        ::Creatives::RenderImageJob.perform_later(generation.id)
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
    end
  end
end
