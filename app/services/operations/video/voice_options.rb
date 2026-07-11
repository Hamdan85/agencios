# frozen_string_literal: true

module Operations
  module Video
    # The available fixed voices + how a director/chat pick resolves to a concrete
    # Cartesia voice_id. Primary source is the LIVE Cartesia library (filtered to
    # the language); the admin `VideoConfig.voice_catalog` is an optional override/
    # supplement (rename, or force a private voice). This is why voice needs no
    # manual setup — the orchestrator picks the best voice for the character from
    # what Cartesia actually offers.
    module VoiceOptions
      module_function

      # [{ id:, name:, gender:, description: }] — live voices first, then admin
      # catalog entries whose id isn't already listed. Empty ⇒ feature stays off.
      def list
        live = Vendors::Cartesia::Actions::ListVoices.call
        live_ids = live.map { |v| v[:id] }
        admin = VideoConfig.instance.voices.filter_map do |name, id|
          next if live_ids.include?(id)

          { id: id, name: name, gender: '', description: I18n.t('operations.video.voice_options.catalog_tag') }
        end
        live + admin
      end

      # Strict: the EXACT pick (by name, case-insensitive, or by raw voice_id),
      # else nil. Used when the user explicitly names a voice (SetVoice) — an
      # unknown name should fail, not silently pick another.
      def resolve(pick)
        p = pick.to_s.strip
        return nil if p.blank?

        opts = list
        by_name = opts.find { |v| v[:name].to_s.casecmp?(p) }
        return by_name[:id] if by_name
        return p if opts.any? { |v| v[:id] == p }

        # Admin catalog exact (label → id, or a raw id present in it).
        cat = VideoConfig.instance.voices
        cat[p] || (cat.value?(p) ? p : nil)
      end

      # Lenient: the pick, else the admin default, else the first available voice
      # (so a video always gets a real voice when any exist). Nil ⇒ no voices at
      # all → the pipeline keeps the model's native audio.
      def resolve_or_default(pick)
        resolve(pick).presence || VideoConfig.instance.default_voice_id.presence || list.first&.dig(:id)
      end
    end
  end
end
