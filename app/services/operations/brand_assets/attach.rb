# frozen_string_literal: true

module Operations
  module BrandAssets
    # Attaches/replaces an owner's brand assets. The owner is any model exposing
    # `has_one_attached :logo` + `:default_creator_avatar` (Client, Workspace).
    # Each asset is optional — only the ones present in the call are (re)attached.
    class Attach < Operations::Base
      def initialize(owner:, logo: nil, default_creator_avatar: nil)
        @owner = owner
        @logo = logo
        @avatar = default_creator_avatar
      end

      def call
        @owner.logo.attach(@logo) if @logo.present?
        @owner.default_creator_avatar.attach(@avatar) if @avatar.present?
        @owner
      end
    end
  end
end
