# frozen_string_literal: true

module Operations
  module Video
    # Removes ONE scene from a video ("corta a cena 2", "reduz para 2 cenas").
    # Later scenes shift down so positions stay contiguous (the chain and the UI
    # number by position). If every remaining scene is ready the video
    # recomposes immediately; otherwise the render chain continues/kicks off.
    # A scene mid-render can be removed too — its orphaned poll finds no record
    # and exits. Credits already spent on the removed scene are not refunded.
    class RemoveScene < Operations::Base
      def initialize(scene:)
        @scene = scene
      end

      def call
        creative = @scene.creative
        raise Operations::Errors::Invalid, 'O vídeo precisa de pelo menos uma cena' if creative.video_scenes.count <= 1

        @scene.destroy!
        creative.video_scenes.ordered.each_with_index do |s, i|
          s.update!(position: i) unless s.position == i
        end

        generation = creative.generation
        remaining = creative.video_scenes.reload.ordered.to_a

        if remaining.all?(&:composable?)
          # The cut may complete the video right away — recompose the remainder.
          generation&.update!(status: :processing) unless generation&.status_processing?
          Compose.call(creative: creative)
        else
          generation&.update!(status: :processing)
          creative.update!(status: :generating) unless creative.status_generating?
          resume_chain(remaining)
        end
        creative
      end

      private

      # The removal may have unblocked the sequential chain (e.g. the FAILED
      # scene was cut): render the first pending scene whose predecessors are
      # all ready. A scene already rendering keeps its in-flight job.
      def resume_chain(remaining)
        return if remaining.any?(&:state_rendering?)

        pending = remaining.select { |s| %w[fresh stale].include?(s.render_state) }.min_by(&:position)
        return unless pending
        return unless remaining.select { |s| s.position < pending.position }.all?(&:state_ready?)

        RenderScene.call(scene: pending)
      end
    end
  end
end
