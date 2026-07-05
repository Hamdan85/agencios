# frozen_string_literal: true

module Controllers
  module VideoScenes
    # GET /creatives/:creative_id/assets/library — reusable elements the user can
    # add to this video (brand avatar/logo + characters/scenarios from the
    # workspace's other videos).
    class AssetLibrary < Base
      def initialize(params:)
        @params = params
      end

      def call
        creative = workspace.creatives.find(@params[:creative_id])
        Operations::Video::AssetLibrary.call(creative: creative)
      end
    end
  end
end
