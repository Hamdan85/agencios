# frozen_string_literal: true

module Operations
  module Video
    # Inserts a NEW scene into a video at a given position ("adiciona uma cena
    # final com a logo"). Later scenes shift up; the scene renders as soon as its
    # predecessors are ready (or immediately when inserted at the end of a ready
    # video). Charged for its seconds. If an already-rendered scene ends up
    # FOLLOWING the insert, it goes stale (charged re-render) so the continuity
    # chain re-links through the new scene.
    class AddScene < Operations::Base
      # extra_reference_urls: media references attached this turn for the new
      # scene; reference_role declares their JOB (Operations::Video::References
      # assignable roles), generic 'reference' when undeclared.
      def initialize(creative:, position:, prompt:, caption: nil, duration_seconds: nil,
                     camera: nil, dialogue: nil, sound_effects: nil, on_screen_text: nil,
                     extra_reference_urls: [], reference_role: nil, reference_descriptions: {})
        @creative       = creative
        @position       = position.to_i
        @prompt         = prompt.to_s.strip
        @caption        = caption
        @duration       = duration_seconds
        @camera         = camera
        @dialogue       = dialogue
        @sound_effects  = sound_effects
        @on_screen_text = on_screen_text
        @extra_refs     = Array(extra_reference_urls).map { |u| u.to_s.strip }.reject(&:blank?)
        @ref_role       = References.assignable_role(reference_role)
        @ref_descriptions = (reference_descriptions || {}).to_h
      end

      def call
        raise Operations::Errors::Invalid, 'A nova cena precisa de uma descrição' if @prompt.blank?

        scenes = @creative.video_scenes.ordered.to_a
        if scenes.size >= PlanScenes::MAX_SCENES
          raise Operations::Errors::Invalid, "O vídeo já tem o máximo de #{PlanScenes::MAX_SCENES} cenas"
        end

        generation = @creative.generation
        pos        = @position.clamp(0, scenes.size)
        mode       = sibling_mode(scenes, generation)
        # A flexible TARGET length (clamped, not snapped) — the render renders a
        # supported clip >= it and compose trims to it, same rule the storyboard follows.
        seed_secs  = (@duration.presence || scenes.last&.duration_seconds || PlanScenes::SCENE_UNIT_SECONDS).to_i
        duration   = seed_secs.clamp(PlanScenes::MIN_SCENE_SECONDS, VideoConfig.instance.clip_seconds_for(mode).max)

        Operations::Credits::Debit.call(
          workspace: @creative.workspace,
          amount: Pricing.credits_for(kind: :video, seconds: duration),
          generation: generation, description: "Adicionar cena #{pos + 1} do vídeo"
        )

        scenes.select { |s| s.position >= pos }.sort_by(&:position)
              .reverse_each { |s| s.update!(position: s.position + 1) }

        sibling = scenes.first
        base_urls  = sibling&.reference_urls || []
        base_roles = sibling&.metadata&.dig('reference_roles') || []
        base_descriptions = Array.new(base_urls.size) { |i| Array(sibling&.metadata&.dig('reference_descriptions'))[i] }
        scene = Scenes::Create.call(
          creative: @creative, position: pos, mode: mode,
          prompt: @prompt, caption: @caption, duration_seconds: duration,
          camera: @camera, dialogue: @dialogue, sound_effects: @sound_effects, on_screen_text: @on_screen_text,
          aspect_ratio: sibling&.aspect_ratio || generation&.params&.dig('aspect_ratio'),
          seed: SecureRandom.hex(6),
          reference_image_urls: base_urls + @extra_refs,
          reference_roles: base_roles + ([@ref_role] * @extra_refs.size),
          reference_descriptions: base_descriptions + @extra_refs.map { |u| @ref_descriptions[u].to_s.strip.presence }
        )

        relink_follower!(pos, generation)
        generation&.update!(status: :processing)
        @creative.update!(status: :generating) unless @creative.status_generating?
        resume_chain
        scene.reload
      end

      private

      def sibling_mode(scenes, generation)
        scenes.first&.mode.presence || generation&.params&.dig('mode').presence || 'avatar'
      end

      # The scene now following the insert was rendered continuing a DIFFERENT
      # predecessor — re-render it (charged) so the video stays one continuous
      # take through the new scene.
      def relink_follower!(pos, generation)
        follower = @creative.video_scenes.find_by(position: pos + 1)
        return unless follower&.state_ready?

        Operations::Credits::Debit.call(
          workspace: @creative.workspace,
          amount: Pricing.credits_for(kind: :video, seconds: follower.duration_seconds),
          generation: generation, description: 'Refazer cena do vídeo (continuidade)'
        )
        follower.update!(render_state: :stale)
      end

      # Kick the chain when it isn't already running: render the first pending
      # scene whose predecessors are all ready (usually the new scene itself).
      def resume_chain
        remaining = @creative.video_scenes.reload.ordered.to_a
        return if remaining.any?(&:state_rendering?)

        pending = remaining.select { |s| %w[fresh stale].include?(s.render_state) }.min_by(&:position)
        return unless pending
        return unless remaining.select { |s| s.position < pending.position }.all?(&:state_ready?)

        RenderScene.call(scene: pending)
      end
    end
  end
end
