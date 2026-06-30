# frozen_string_literal: true

module Operations
  module Workspaces
    # Attaches/replaces a workspace's (agency's) brand assets. Each asset is
    # optional — only the ones present in the call are (re)attached.
    class UpdateBrandAssets < Operations::Base
      def initialize(workspace:, logo: nil, default_creator_avatar: nil)
        @workspace = workspace
        @logo = logo
        @avatar = default_creator_avatar
      end

      def call
        @workspace.logo.attach(@logo) if @logo.present?
        @workspace.default_creator_avatar.attach(@avatar) if @avatar.present?
        @workspace
      end
    end
  end
end
