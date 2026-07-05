# frozen_string_literal: true

module Api
  module V1
    # Scenes of a generated video — listed for the result timeline, edited one at
    # a time (caption free, prompt re-renders just that scene).
    class VideoScenesController < BaseController
      def index      = render_ok(Controllers::VideoScenes::Index.call(params:))
      def update     = render_ok(Controllers::VideoScenes::Update.call(params:))
      def chat       = render_ok(Controllers::VideoScenes::Chat.call(params:))
      def finalize   = render_ok(Controllers::VideoScenes::Finalize.call(params:))
      def assets         = render_ok(Controllers::VideoScenes::Assets.call(params:))
      def asset_library  = render_ok(Controllers::VideoScenes::AssetLibrary.call(params:))
      def regenerate_asset = render_ok(Controllers::VideoScenes::RegenerateAsset.call(params:))
      def add_asset      = render_ok(Controllers::VideoScenes::AddAsset.call(params:))
      def remove_asset   = render_ok(Controllers::VideoScenes::RemoveAsset.call(params:))
    end
  end
end
