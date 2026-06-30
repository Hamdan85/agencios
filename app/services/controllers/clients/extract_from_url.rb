# frozen_string_literal: true

module Controllers
  module Clients
    # AI extraction from a landing page URL: fetches the brand's site and returns
    # a full client draft (contact + brand + positioning) for the creation wizard
    # to pre-fill. Stateless — runs BEFORE the client exists. Gated to client
    # creators (managers+), mirroring PositioningPreview.
    class ExtractFromUrl < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Client, :create?)
        extracted = Operations::Ai::ExtractClientFromUrl.call(url: @params[:url].to_s)
        { extracted: extracted }
      end
    end
  end
end
