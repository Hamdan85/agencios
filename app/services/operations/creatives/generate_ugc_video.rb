# frozen_string_literal: true

module Operations
  module Creatives
    # Kicks off a UGC avatar video render. Produces a Creative (generated, still
    # generating) and a `video` Generation in `processing` — the render is async.
    #
    # The script falls back to the ticket's scoping script, and the aspect ratio
    # comes from the creative type's spec (e.g. 9:16 for ugc_video / reel). A
    # webhook / PollHeygenVideoJob finalizes the Creative + Generation and meters
    # it (Stripe) + records the HeyGen vendor cost (AiUsageLog).
    class GenerateUgcVideo < Operations::Base
      PROVIDER = 'heygen'

      def initialize(ticket: nil, script: nil, avatar: nil, voice: nil, creative_type: nil, client_id: nil)
        @ticket        = ticket
        @script        = script
        @avatar        = avatar
        @voice         = voice
        @creative_type = creative_type
        @client_id     = client_id
      end

      def call
        ctx    = ::Tickets::CreativeContext.for(@ticket, creative_type: type, client: resolve_client)
        ensure_client_active!(ctx.client)
        script = @script.presence || ctx.script
        aspect = ctx.aspect_ratio.presence || '9:16'

        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: ctx.creative_type || type,
          source: :generated,
          status: :generating,
          provider: PROVIDER
        )

        generation = workspace.generations.create!(
          user: Current.user,
          creative: creative,
          kind: :video,
          status: :processing,
          provider: PROVIDER,
          params: { script: script, avatar: @avatar, voice: @voice, aspect_ratio: aspect,
                    estimated_seconds: Pricing::DEFAULT_VIDEO_SECONDS }
        )

        # Hold an estimate of the credit cost BEFORE kicking off the (paid) render.
        # FinalizeGeneration reconciles it to the real duration on completion.
        # Raises InsufficientCredits (→ 402) if the wallet can't cover the estimate.
        Operations::Credits::Debit.call(
          workspace: workspace,
          amount: Pricing.credits_for(kind: :video, seconds: Pricing::DEFAULT_VIDEO_SECONDS),
          generation: generation,
          description: 'Geração de vídeo (estimativa)'
        )

        begin
          video_id = Vendors::Heygen::Actions::GenerateVideo.call(
            avatar: @avatar,
            voice: @voice,
            script: script,
            aspect_ratio: aspect,
            dimension: dimension(ctx)
          )
        rescue StandardError
          Operations::Credits::Refund.call(generation: generation)
          generation.update!(status: :failed)
          creative.update!(status: :failed)
          raise
        end

        generation.update!(external_id: video_id)

        broadcast(event: 'generation_progress', id: generation.id, kind: 'video', status: 'processing')
        generation
      end

      private

      def type
        @creative_type.presence || @ticket&.creative_type.presence || 'ugc_video'
      end

      def resolve_client
        return nil if @client_id.blank?

        workspace.clients.find_by(id: @client_id)
      end

      def dimension(ctx)
        return { width: ctx.width, height: ctx.height } if ctx.width && ctx.height

        { width: 1080, height: 1920 }
      end

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
