# frozen_string_literal: true

module Operations
  module Video
    # Edits ONE scene without redoing the whole video.
    #   * caption only               → FREE, no re-render (a label in the editor UI)
    #   * prompt / dialogue /
    #     on_screen_text changed     → re-render ONLY this scene (charged for its
    #                                  seconds); the video recomposes when ready.
    #
    # dialogue and on_screen_text are first-class creative fields (exact PT-BR
    # spoken line / lettering) — passing an empty string CLEARS them; omitting
    # them keeps the current values. A re-render reopens the generation (back to
    # processing) so Compose runs again once every scene is ready. Raises
    # InsufficientCredits (→ 402) if the wallet can't cover the re-render.
    class EditScene < Operations::Base
      # restyle: a re-render that should BREAK from the scene's current look
      # (RenderScene then skips the keep-look first-frame conditioning).
      # add_reference_urls: reference images the user attached this turn, appended
      # to the scene's references (role 'reference') and re-rendered so the model
      # draws on them.
      def initialize(scene:, caption: nil, prompt: nil, dialogue: nil, on_screen_text: nil,
                     restyle: nil, add_reference_urls: [])
        @scene          = scene
        @caption        = caption
        @prompt         = prompt.to_s.strip.presence
        @dialogue_given = !dialogue.nil?
        @dialogue       = dialogue.to_s.strip.presence
        @text_given     = !on_screen_text.nil?
        @text           = on_screen_text.to_s.strip.presence
        @restyle        = restyle
        @new_refs       = Array(add_reference_urls).map { |u| u.to_s.strip }.reject(&:blank?)
      end

      def call
        @scene.update!(caption: @caption) unless @caption.nil?

        # A dialogue change on a SILENT video is a no-op the model can't honor —
        # drop it (don't charge, don't re-render) so the user isn't billed for a
        # render that can never contain the requested speech.
        @dialogue_given = false if @dialogue_given && silent?

        # Newly attached reference images are appended before the re-render so
        # the submitted scene carries them.
        append_references!

        # Re-render when any creative field changed, references were attached, a
        # new look is requested (restyle), or a value is given for a scene that
        # has no good render (failed / never rendered / stale) — that's a RETRY,
        # and an identical value must not be a silent no-op. An edit on a scene
        # whose render is IN FLIGHT supersedes it: the outdated render is
        # discarded when its poll completes and the new fields render instead.
        rerender! if render_requested? && (changed? || refs_added? || restyle_requested? || retryable? || @scene.state_rendering?)

        @scene
      end

      private

      def render_requested?
        @prompt.present? || @dialogue_given || @text_given || restyle_requested? || refs_added?
      end

      def refs_added? = @new_refs.any?

      # Append the attached references (role 'reference') to the scene, keeping
      # the url list and the parallel role list in sync.
      def append_references!
        return unless refs_added?

        roles = Array(@scene.metadata['reference_roles'])
        roles += ['reference'] * @new_refs.size
        @scene.update!(
          reference_image_urls: @scene.reference_urls + @new_refs,
          metadata: @scene.metadata.merge('reference_roles' => roles)
        )
      end

      def restyle_requested?
        @restyle == true
      end

      def retryable?
        %w[failed fresh stale].include?(@scene.render_state)
      end

      def changed?
        (@prompt.present? && @prompt != @scene.prompt.to_s.strip) ||
          (@dialogue_given && @dialogue != @scene.metadata['dialogue'].to_s.strip.presence) ||
          (@text_given && @text != @scene.metadata['on_screen_text'].to_s.strip.presence)
      end

      # The generation opted out of sound → no speech can ever play.
      def silent?
        params = @scene.creative.generation&.params
        params&.key?('with_audio') && ActiveModel::Type::Boolean.new.cast(params['with_audio']) == false
      end

      def rerender!
        generation = @scene.creative.generation
        superseding = @scene.state_rendering?

        Operations::Credits::Debit.call(
          workspace: @scene.workspace,
          amount: Pricing.credits_for(kind: :video, seconds: @scene.duration_seconds),
          generation: generation, description: "Refazer cena #{@scene.position + 1} do vídeo"
        )

        # Reopen the generation so Compose runs again once the scene is ready.
        # A failed creative is reopened too — a retry IS leaving the failed state.
        generation&.update!(status: :processing)
        @scene.creative.update!(status: :generating) if @scene.creative.status_ready? || @scene.creative.status_failed?

        meta = @scene.metadata.merge('restyle' => @restyle == true)
        meta['dialogue'] = @dialogue if @dialogue_given
        meta['on_screen_text'] = @text if @text_given
        @scene.update!(prompt: @prompt || @scene.prompt, render_state: :stale, metadata: meta.compact)

        # Continuity: a scene only renders right away when every earlier scene is
        # ready (its predecessor's last frame exists). Otherwise it stays `stale`
        # and the per-scene poll chain picks it up in order as predecessors finish.
        # A superseded scene never submits here either — its in-flight poll sees
        # `stale` on completion, voids the old render, and submits the new fields.
        Operations::Video::RenderScene.call(scene: @scene) unless predecessor_pending? || superseding
      end

      def predecessor_pending?
        @scene.creative.video_scenes.where('position < ?', @scene.position)
              .where.not(render_state: :ready).exists?
      end
    end
  end
end
