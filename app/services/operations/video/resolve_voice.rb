# frozen_string_literal: true

module Operations
  module Video
    # Turns the orchestrator's VOICE pick into the concrete generation-params the
    # render (and, optionally, compose) uses: the resolved Cartesia voice_id +
    # the delivery tone/speed. One fixed voice per video ⇒ the same voice in
    # every scene. Mirrors Operations::Video::ResolveMusic.
    #
    # spec keys (all optional): voice (a catalog label OR a raw voice_id), speed.
    # Returns the params hash to MERGE onto the generation (empty ⇒ no fixed voice
    # → the pipeline keeps the model's native audio, like an empty music catalog).
    class ResolveVoice < Operations::Base
      SPEEDS = %w[slow normal fast].freeze

      def initialize(spec:)
        @spec = (spec || {}).transform_keys(&:to_s)
      end

      def call
        voice_id = VoiceOptions.resolve_or_default(@spec['voice'])
        return {} if voice_id.blank?

        {
          'voice_id' => voice_id,
          'voice_label' => @spec['voice'].to_s.strip.presence,
          'voice_speed' => (SPEEDS.include?(@spec['speed'].to_s) ? @spec['speed'].to_s : nil)
        }.compact
      end
    end
  end
end
