# frozen_string_literal: true

module Controllers
  module VideoScenes
    # PATCH /video_scenes/:id — edit one scene. A caption change is free; a prompt
    # change re-renders only this scene (charged). Guests cannot edit; editing a
    # scene can spend credits, so it's billing-gated like generation.
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        scene = workspace.video_scenes.find(@params[:id])
        attrs = scene_params
        require_billing! if attrs[:prompt].present?

        Operations::Video::EditScene.call(
          scene: scene, caption: attrs[:caption], prompt: attrs[:prompt]
        )
        { scene: serialize(scene.reload, VideoSceneSerializer) }
      end

      private

      def scene_params
        raw = @params[:scene] || @params
        raw.permit(:caption, :prompt).to_h.symbolize_keys
      end
    end
  end
end
