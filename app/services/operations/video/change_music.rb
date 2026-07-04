# frozen_string_literal: true

module Operations
  module Video
    # Changes the background-music track of a video WITHOUT re-rendering any scene
    # — the music is burned at compose, so a new mood is just a re-mix. FREE (no
    # credits, no model calls). The track only ever changes when the user asks;
    # generation auto-picks it once and it stays put otherwise.
    #   * a known mood      → resolve its catalog track, recompose
    #   * 'none' / nil mood → remove the music, recompose
    #
    # A silent video (with_audio: false) can't carry music — raises Invalid.
    # mood/query: the user's ask ("algo mais animado" → mood, or free words →
    # query). 'none' removes the music. The mix params are re-derived (or kept
    # from the current track's settings when the user only nudges the song).
    class ChangeMusic < Operations::Base
      MUSIC_KEYS = %w[music_mood music_query music_url music_title music_attribution
                      music_volume music_fade_in music_fade_out music_duck].freeze

      def initialize(creative:, mood: nil, query: nil)
        @creative = creative
        @mood     = mood.to_s.strip.downcase
        @query    = query.to_s.strip
      end

      def call
        generation = @creative.generation
        raise Operations::Errors::Invalid, 'Vídeo sem geração associada' unless generation
        raise Operations::Errors::Invalid, 'Este vídeo é silencioso — não leva música' if silent?(generation)

        params = generation.params || {}
        generation.update!(params: params.except(*MUSIC_KEYS).merge(resolved_music(params)))

        # Re-burn the soundtrack over the already-rendered scenes (no re-render).
        Compose.call(creative: @creative, remix: true) if @creative.video_scenes.ordered.all?(&:composable?)
        @creative
      end

      private

      def removing? = @mood == 'none' || @mood == 'nenhuma'

      # Re-search the open base for the new mood/query, keeping the previous mix
      # knobs (volume/fades/duck) so only the SONG changes.
      def resolved_music(params)
        return {} if removing? || (@mood.blank? && @query.blank?)

        ResolveMusic.call(spec: {
          'query' => @query.presence || @mood, 'mood' => @mood.presence,
          'volume' => params['music_volume'], 'fade_in' => params['music_fade_in'],
          'fade_out' => params['music_fade_out'], 'duck' => params['music_duck']
        })
      end

      def silent?(generation)
        params = generation.params || {}
        params.key?('with_audio') && ActiveModel::Type::Boolean.new.cast(params['with_audio']) == false
      end
    end
  end
end
