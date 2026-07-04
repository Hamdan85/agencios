# frozen_string_literal: true

module Operations
  module Video
    # Turns the orchestrator's MUSIC SPEC (a search query + the ffmpeg mix
    # parameters it chose) into the concrete generation-params the compose step
    # burns in: the resolved track URL + the mix knobs (volume, fades, duck).
    #
    # Source: Jamendo (an open royalty-free base with a real search API); falls
    # back to the admin catalog (VideoConfig.music_tracks) when Jamendo is not
    # configured or returns nothing, else no music. The orchestrator OWNS every
    # ffmpeg parameter, so compose is deterministic.
    #
    # spec keys (all optional): query, mood, volume, fade_in, fade_out, duck.
    # Returns the params hash to MERGE onto the generation (empty ⇒ no music).
    class ResolveMusic < Operations::Base
      VOLUME_RANGE = (0.05..0.6)
      FADE_IN_RANGE = (0.0..3.0)
      FADE_OUT_RANGE = (0.0..5.0)
      DEFAULTS = { volume: 0.28, fade_in: 1.0, fade_out: 2.0, duck: true }.freeze

      def initialize(spec:)
        @spec = (spec || {}).transform_keys(&:to_s)
      end

      def call
        query = @spec['query'].to_s.strip
        mood  = @spec['mood'].to_s.strip.downcase.presence
        return {} if query.blank? && mood.blank?

        track = find_track(query, mood)
        return {} unless track

        {
          'music_mood' => mood,
          'music_query' => query.presence,
          'music_url' => track[:url] || track['url'],
          'music_title' => track[:title] || track['title'],
          'music_attribution' => track[:attribution] || track['attribution'],
          'music_volume' => clamp(@spec['volume'], VOLUME_RANGE, DEFAULTS[:volume]),
          'music_fade_in' => clamp(@spec['fade_in'], FADE_IN_RANGE, DEFAULTS[:fade_in]),
          'music_fade_out' => clamp(@spec['fade_out'], FADE_OUT_RANGE, DEFAULTS[:fade_out]),
          'music_duck' => @spec.key?('duck') ? ActiveModel::Type::Boolean.new.cast(@spec['duck']) : DEFAULTS[:duck]
        }.compact
      end

      private

      # Jamendo first (the open base the orchestrator searched), then the manual
      # catalog by mood, else nil (no music).
      def find_track(query, mood)
        term = query.presence || mood
        track = Vendors::Jamendo::Actions::SearchTracks.call(query: term, tags: mood)
        return track if track

        mood.present? ? VideoConfig.instance.music_track_for(mood) : nil
      end

      def clamp(value, range, default)
        n = value.to_f
        return default if value.nil? || n.zero?

        n.clamp(range.begin, range.end).round(2)
      end
    end
  end
end
