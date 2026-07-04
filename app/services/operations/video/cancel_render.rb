# frozen_string_literal: true

module Operations
  module Video
    # Stops an in-flight video generation ("para de gerar", "cancela"). Scenes
    # currently rendering are marked failed (their vendor jobs are abandoned —
    # the orphaned poll finds a failed scene and exits); queued scenes stay put.
    # FailGeneration settles the ledger (refunds the newest charge) and fails
    # the generation + creative. Everything remains editable afterwards: the
    # user can retry, remove or rewrite scenes through the chat.
    class CancelRender < Operations::Base
      REASON = 'Cancelado pelo usuário'

      def initialize(creative:)
        @creative = creative
      end

      def call
        generation = @creative.generation
        unless generation&.status_processing?
          raise Operations::Errors::Invalid, 'Nada para cancelar — o vídeo não está em processamento'
        end

        @creative.video_scenes.state_rendering.find_each do |scene|
          scene.update!(render_state: :failed,
                        metadata: scene.metadata.merge('failure' => REASON))
        end

        Operations::Creatives::FailGeneration.call(generation: generation, reason: REASON)
        @creative
      end
    end
  end
end
