# frozen_string_literal: true

module Controllers
  module VideoScenes
    # GET /creatives/:creative_id/assets — the video's assets (characters,
    # scenarios, music) for the editor's Assets tab.
    class Assets < Base
      def initialize(params:)
        @params = params
      end

      def call
        creative = workspace.creatives.find(@params[:creative_id])
        { assets: Operations::Video::AssetList.call(creative: creative) }
      end
    end
  end
end
