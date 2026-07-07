# frozen_string_literal: true

module Controllers
  module Settings
    # Attaches the workspace's brand assets (logo and/or creator avatar) from a
    # multipart upload. Manager-gated, like the rest of settings management.
    class UpdateBrandAssets < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        Operations::BrandAssets::Attach.call(
          owner: workspace, logo: @params[:logo], default_creator_avatar: @params[:default_creator_avatar]
        )
        Payload.new(Settings.ensure_setting!(workspace)).call
      end
    end
  end
end
