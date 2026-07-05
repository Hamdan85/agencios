# frozen_string_literal: true

module Controllers
  module VideoScenes
    # POST /creatives/:creative_id/assets/add — add an element (uploaded file or a
    # library asset) to the video under a role. Free (no re-render); the element is
    # used on the next render. Guests cannot edit.
    #   body { url, role, description? }
    class AddAsset < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        creative = workspace.creatives.find(@params[:creative_id])

        Operations::Video::AddReference.call(
          creative: creative, url: @params[:url], role: @params[:role], description: @params[:description]
        )

        creative.reload
        { assets: Operations::Video::AssetList.call(creative: creative) }
      end
    end
  end
end
