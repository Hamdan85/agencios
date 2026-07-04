# frozen_string_literal: true

module Controllers
  module VideoScenes
    # GET /creatives/:creative_id/scenes — the scenes of a generated video, in
    # order, for the result view's timeline.
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        creative = workspace.creatives.find(@params[:creative_id])
        {
          creative: serialize(creative, CreativeSerializer),
          scenes: serialize_collection(creative.video_scenes.ordered, VideoSceneSerializer),
          messages: creative.chat_messages
        }
      end
    end
  end
end
