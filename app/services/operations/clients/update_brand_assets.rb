# frozen_string_literal: true

module Operations
  module Clients
    # Attaches/replaces a client's brand assets. Each asset is optional — only the
    # ones present in the call are (re)attached.
    class UpdateBrandAssets < Operations::Base
      def initialize(client:, logo: nil, default_creator_avatar: nil)
        @client = client
        @logo = logo
        @avatar = default_creator_avatar
      end

      def call
        @client.logo.attach(@logo) if @logo.present?
        @client.default_creator_avatar.attach(@avatar) if @avatar.present?
        @client
      end
    end
  end
end
