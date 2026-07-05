# frozen_string_literal: true

module Vendors
  module Cartesia
    module Actions
      # Synthesize one spoken line in a fixed voice → { bytes:, content_type: }
      # (or nil when Cartesia isn't configured / it errors). Never raises to the
      # caller — a missing voice must never fail a video render (the pipeline
      # falls back to the model's native audio), mirroring EpidemicSound::SearchTracks.
      class Synthesize
        def self.call(...) = new(...).call

        def initialize(text:, voice_id:, language: 'pt', speed: nil)
          @text     = text
          @voice_id = voice_id
          @language = language
          @speed    = speed
        end

        def call
          return nil if @text.to_s.strip.blank? || @voice_id.to_s.strip.blank?

          client = Vendors::Cartesia::Client.new
          return nil unless client.configured?

          client.synthesize(text: @text, voice_id: @voice_id, language: @language, speed: @speed)
        rescue StandardError => e
          Rails.logger.warn("[Cartesia::Synthesize] #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
