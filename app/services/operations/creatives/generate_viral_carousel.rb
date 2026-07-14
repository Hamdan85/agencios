# frozen_string_literal: true

module Operations
  module Creatives
    # Starts a VIRAL-carousel generation. This is the FAST, in-request half (the
    # project rule for ALL generation kinds): it validates the client, creates
    # the Creative (generating) + the tracked `carousel` Generation, charges
    # prepaid credits (raises InsufficientCredits → 402 before any vendor spend)
    # and hands off to Creatives::RenderCarouselJob. The copy AI call, the image
    # slots and the Chromium render NEVER run in-request — the UI gets the
    # processing generation back immediately and receives the result via Action
    # Cable (`generation_done` on generations_<workspace_id>, `creative_ready`
    # on ticket_<id>). The heavy lifting lives in Operations::Creatives::RenderCarousel.
    class GenerateViralCarousel < Operations::Base
      PROVIDER   = 'carousel_generator'
      COST_CENTS = 30

      def initialize(ticket: nil, slides: nil, params: {})
        @ticket = ticket
        @slides = slides
        @params = (params || {}).to_h
      end

      def call
        ensure_client_active!(resolve_client || @ticket&.project&.client)

        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: 'carousel',
          source: :generated,
          status: :generating,
          provider: PROVIDER
        )

        generation = workspace.generations.create!(
          user: Current.user,
          creative: creative,
          kind: :carousel,
          status: :processing,
          provider: PROVIDER,
          cost_cents: COST_CENTS,
          # The render job re-derives everything from here (slides request included).
          params: @params.merge(slides: @slides).compact,
          result: {}
        )

        # Surface the "Gerando…" card immediately — the gallery/board are
        # subscribed to this channel.
        Broadcaster.generations(workspace.id, 'generation_progress',
                                id: generation.id, kind: 'carousel', status: 'processing')

        # A carousel debits prepaid credits like an image (Pricing.credits_for →
        # 0 makes it free again). Charge BEFORE any vendor spend; on failure the
        # records are failed and refunded.
        begin
          Operations::Credits::Debit.call(
            workspace: workspace,
            amount: Pricing.credits_for(kind: :carousel),
            generation: generation
          )
        rescue StandardError => e
          Operations::Creatives::FailGeneration.call(generation: generation, reason: e.message)
          raise
        end

        ::Creatives::RenderCarouselJob.perform_later(generation.id)
        generation
      end

      private

      # The client this carousel is FOR (studio passes client_id; ticket path
      # falls back to the ticket's client).
      def resolve_client
        id = @params[:client_id] || @params['client_id']
        return nil if id.blank?

        workspace.clients.find_by(id: id)
      end
    end
  end
end
