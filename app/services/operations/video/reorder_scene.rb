# frozen_string_literal: true

module Operations
  module Video
    # Moves ONE scene to a new position ("a cena 3 vem antes da 2"). FREE: the
    # rendered clips are only re-ordered and the video recomposes — nothing is
    # re-rendered, so the seams between reordered scenes may show (the footage
    # was rendered in the original order). The chat agent warns about that and
    # can re-render specific scenes afterwards if the user wants them re-linked.
    class ReorderScene < Operations::Base
      def initialize(scene:, to_position:)
        @scene = scene
        @to    = to_position.to_i
      end

      def call
        creative = @scene.creative
        scenes   = creative.video_scenes.ordered.to_a
        to       = @to.clamp(0, scenes.size - 1)
        return creative if to == @scene.position

        list = scenes.reject { |s| s.id == @scene.id }
        list.insert(to, @scene)
        list.each_with_index { |s, i| s.update!(position: i) unless s.position == i }

        recompose(creative)
        creative
      end

      private

      def recompose(creative)
        generation = creative.generation
        return unless creative.video_scenes.reload.ordered.all?(&:composable?)

        generation&.update!(status: :processing) unless generation&.status_processing?
        Compose.call(creative: creative)
      end
    end
  end
end
