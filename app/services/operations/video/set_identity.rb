# frozen_string_literal: true

module Operations
  module Video
    # Changes the LOCKED project identity (character / wardrobe / scenario /
    # palette / style / whether there's a character at all) and RE-RENDERS every
    # scene so the new identity is applied consistently — the director changing
    # the cast/wardrobe/look mid-project. Charged like any re-render (each scene
    # costs its seconds). The scenes keep their prompts/dialogue/text; only the
    # injected identity block changes.
    #
    # Merges onto the current identity: fields the user didn't touch stay put.
    class SetIdentity < Operations::Base
      TEXT_KEYS = %w[character wardrobe scenario palette style].freeze

      def initialize(creative:, changes:)
        @creative = creative
        @changes  = (changes || {}).transform_keys(&:to_s)
      end

      def call
        generation = @creative.generation
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_identity.no_generation') unless generation

        scenes = @creative.video_scenes.ordered.to_a
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_identity.no_scenes') if scenes.empty?
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.set_identity.busy') if busy?(scenes)

        generation.update!(params: (generation.params || {}).merge('identity' => merged_identity(generation)))

        Operations::Credits::Debit.call(
          workspace: @creative.workspace,
          amount: Pricing.credits_for(kind: :video, seconds: scenes.sum { |s| s.duration_seconds.to_i }),
          generation: generation, description: ledger_description
        )
        generation.update!(status: :processing)
        @creative.update!(status: :generating) unless @creative.status_generating?

        # Whole video re-renders with the new identity — queue all, start the chain.
        scenes.each { |s| s.update!(render_state: :stale) }
        RenderScene.call(scene: scenes.first)
        @creative
      end

      private

      def merged_identity(generation)
        current = generation.params&.dig('identity') || {}
        merged = current.dup
        merged['has_character'] = ActiveModel::Type::Boolean.new.cast(@changes['has_character']) if @changes.key?('has_character')
        TEXT_KEYS.each { |k| merged[k] = @changes[k].to_s.strip.presence if @changes.key?(k) }
        merged.compact
      end

      def busy?(scenes)
        scenes.any? { |s| %w[rendering fresh].include?(s.render_state) }
      end

      # Persisted to the workspace credit ledger (a team-shared artifact), so it
      # is rendered once in the workspace language at write time.
      def ledger_description
        I18n.with_locale(workspace_locale(@creative.workspace)) do
          I18n.t('operations.video.ledger.set_identity')
        end
      end

      def workspace_locale(ws) = I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
    end
  end
end
