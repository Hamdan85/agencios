# frozen_string_literal: true

module Operations
  module Video
    # Approves a DRAFT video: re-renders every scene with the FINAL (best) model,
    # keeping the storyboard, prompts and captions the user iterated on. Charged
    # like any render (credits held for the total duration, reconciled at
    # compose). Scenes re-render sequentially so frame continuity is preserved;
    # Compose runs again when the chain finishes.
    class UpgradeQuality < Operations::Base
      # Ledger description of the upgrade's credit HOLD — Compose recognizes it
      # to true-up the estimate to the real rendered duration.
      HOLD_DESCRIPTION = 'Vídeo em alta qualidade (upgrade)'

      def initialize(creative:)
        @creative = creative
      end

      def call
        generation = @creative.generation
        raise Operations::Errors::Invalid, 'Vídeo sem geração associada' unless generation
        raise Operations::Errors::Invalid, 'O vídeo ainda está em processamento' if busy?
        raise Operations::Errors::Invalid, 'Este vídeo já está em alta qualidade' if final?(generation)

        scenes = @creative.video_scenes.ordered.to_a
        raise Operations::Errors::Invalid, 'Vídeo sem cenas' if scenes.empty?

        total_seconds = scenes.sum { |s| s.duration_seconds.to_i }
        Operations::Credits::Debit.call(
          workspace: @creative.workspace,
          amount: Pricing.credits_for(kind: :video, seconds: total_seconds),
          generation: generation, description: HOLD_DESCRIPTION
        )

        generation.update!(status: :processing, params: generation.params.merge('quality' => 'final'))
        @creative.update!(status: :generating,
                          metadata: @creative.metadata.merge('quality' => 'final'))
        # Whole storyboard re-renders: queue everything, start the chain at scene 1.
        scenes.each { |s| s.update!(render_state: :stale) }
        RenderScene.call(scene: scenes.first)

        @creative
      end

      private

      def busy?
        @creative.status_generating? ||
          @creative.video_scenes.where(render_state: %i[rendering fresh]).exists?
      end

      def final?(generation)
        generation.params&.fetch('quality', 'final') == 'final'
      end
    end
  end
end
