# frozen_string_literal: true

module Vendors
  module Cartesia
    module Actions
      # The available Cartesia voices for the language (cached — the library
      # rarely changes and this is called at plan/chat time). Never raises: an
      # unconfigured/errored lookup returns [] (the pipeline degrades to no fixed
      # voice), mirroring EpidemicSound::SearchTracks. Only a NON-empty result is
      # cached, so a transient failure doesn't blank voices for the whole TTL.
      class ListVoices
        CACHE_KEY = 'cartesia:voices'
        TTL = 6.hours

        def self.call(...) = new(...).call

        def initialize(language: VideoConfig::VOICE_LANGUAGE)
          @language = language
        end

        def call
          cached = Rails.cache.read(cache_key)
          return cached if cached.present?

          list = fetch
          Rails.cache.write(cache_key, list, expires_in: TTL) if list.present?
          list
        rescue StandardError => e
          Rails.logger.warn("[Cartesia::ListVoices] #{e.class}: #{e.message}")
          []
        end

        private

        def cache_key = "#{CACHE_KEY}:#{@language}"

        def fetch
          client = Vendors::Cartesia::Client.new
          client.configured? ? client.voices(language: @language) : []
        end
      end
    end
  end
end
