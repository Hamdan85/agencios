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
      def initialize(creative:)
        @creative = creative
      end

      def call
        generation = @creative.generation
        unless generation&.status_processing?
          raise Operations::Errors::Invalid, I18n.t('operations.video.errors.cancel_render.nothing')
        end

        cancel_reason = reason
        @creative.video_scenes.state_rendering.find_each do |scene|
          scene.update!(render_state: :failed,
                        metadata: scene.metadata.merge('failure' => cancel_reason))
        end

        Operations::Creatives::FailGeneration.call(generation: generation, reason: cancel_reason)
        @creative
      end

      private

      # Stored on the scene + generation as the failure cause (a workspace-visible
      # artifact), so it is rendered once in the workspace language.
      def reason
        I18n.with_locale(workspace_locale(@creative.workspace)) do
          I18n.t('operations.video.cancel.reason')
        end
      end

      def workspace_locale(ws) = I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
    end
  end
end
