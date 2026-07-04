# frozen_string_literal: true

module Vendors
  module OpenRouter
    module Actions
      # Download a completed OpenRouter video asset to an IO. OpenRouter serves
      # the finished clip behind the API key (a bare fetch 401s), so downloading
      # goes through the vendor which attaches the bearer token.
      class DownloadVideo
        def self.call(...) = new(...).call

        def initialize(url:)
          @url = url
        end

        def call
          Vendors::OpenRouter::Video.new.download(@url)
        end
      end
    end
  end
end
