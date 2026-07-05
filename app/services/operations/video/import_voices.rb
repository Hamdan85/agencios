# frozen_string_literal: true

module Operations
  module Video
    # Imports the available Cartesia voices for the language into the admin
    # catalog (VideoConfig.voice_catalog) so they're VISIBLE + selectable in the
    # internal admin and stay usable even offline. Fresh fetch (bypasses the
    # ListVoices cache); sets a default voice when none is set. Returns the count
    # imported (0 when Cartesia isn't configured / nothing found).
    class ImportVoices < Operations::Base
      def initialize(language: VideoConfig::VOICE_LANGUAGE)
        @language = language
      end

      def call
        client = Vendors::Cartesia::Client.new
        return 0 unless client.configured?

        voices = client.voices(language: @language)
        return 0 if voices.blank?

        cfg = VideoConfig.first_or_create!
        # Label = the Cartesia display name (already descriptive, e.g.
        # "Isabella - Warm Storyteller"); merged so admin renames/customs survive.
        catalog = voices.to_h { |v| [v[:name].presence || v[:id], v[:id]] }
        cfg.voice_catalog = cfg.voices.merge(catalog)
        cfg.default_voice_id = voices.first[:id] if cfg.default_voice_id.blank?
        cfg.save!
        voices.size
      end
    end
  end
end
