# frozen_string_literal: true

module Controllers
  module VideoScenes
    # POST /creatives/:creative_id/assets/remove — remove an element from the video
    # (drops the reference from every scene, or clears the identity field). Free (no
    # re-render). Guests cannot edit.
    #   body { key }  (an asset key from the list — a URL or "identity:<field>")
    class RemoveAsset < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        creative = workspace.creatives.find(@params[:creative_id])

        Operations::Video::RemoveReference.call(creative: creative, key: @params[:key])

        creative.reload
        { assets: Operations::Video::AssetList.call(creative: creative) }
      end
    end
  end
end
