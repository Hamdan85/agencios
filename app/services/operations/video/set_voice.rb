# frozen_string_literal: true

module Operations
  module Video
    # Changes the video's FIXED voice (the Cartesia voice_id) and RE-RENDERS every
    # scene so the new voice is baked in via the lip-sync audio reference — the
    # director swapping the narrator/speaker mid-project. Charged like any
    # re-render (each scene costs its seconds). Mirrors SetIdentity.
    #
    # The pick is a catalog label OR a raw voice_id; it's resolved through
    # VideoConfig. Clears each scene's synthesized clip so it re-synthesizes in
    # the new voice on the next render.
    class SetVoice < Operations::Base
      def initialize(creative:, voice:)
        @creative = creative
        @voice    = voice.to_s.strip
      end

      def call
        generation = @creative.generation
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_voice.no_generation') unless generation

        voice_id = VoiceOptions.resolve(@voice)
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_voice.voice_not_found') if voice_id.blank?

        scenes = @creative.video_scenes.ordered.to_a
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_voice.no_scenes') if scenes.empty?
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_voice.busy') if busy?(scenes)

        generation.update!(params: (generation.params || {}).merge(
          'voice_id' => voice_id, 'voice_label' => @voice.presence
        ).compact)

        Operations::Credits::Debit.call(
          workspace: @creative.workspace,
          amount: Pricing.credits_for(kind: :video, seconds: scenes.sum { |s| s.duration_seconds.to_i }),
          generation: generation, description: ledger_description
        )
        generation.update!(status: :processing)
        @creative.update!(status: :generating) unless @creative.status_generating?

        # Drop the old voice clips + fingerprints so each scene re-synthesizes in
        # the new voice, then re-render the whole video.
        scenes.each do |s|
          s.voice_clip.purge if s.voice_clip.attached?
          s.update!(render_state: :stale, metadata: s.metadata.except('voice_fingerprint'))
        end
        RenderScene.call(scene: scenes.first)
        @creative
      end

      private

      # Persisted to the workspace credit ledger (a team-shared artifact), so it
      # is rendered once in the workspace language at write time.
      def ledger_description
        I18n.with_locale(workspace_locale(@creative.workspace)) do
          I18n.t('operations.video.ledger.set_voice')
        end
      end

      def workspace_locale(ws) = I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale

      def busy?(scenes)
        scenes.any? { |s| %w[rendering fresh].include?(s.render_state) }
      end
    end
  end
end
