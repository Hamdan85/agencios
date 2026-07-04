# frozen_string_literal: true

module Controllers
  module VideoScenes
    # POST /creatives/:creative_id/video_finalize — approve the draft: re-render
    # the whole storyboard with the FINAL model. Spends credits, so it's gated
    # like generation.
    class Finalize < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        creative = workspace.creatives.find(@params[:creative_id])

        Operations::Video::UpgradeQuality.call(creative: creative)
        creative.reload

        {
          creative: serialize(creative, CreativeSerializer),
          scenes: serialize_collection(creative.video_scenes.ordered, VideoSceneSerializer),
          messages: creative.chat_messages
        }
      end
    end
  end
end
