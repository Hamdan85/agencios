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
      def initialize(creative:, position:, prompt:, caption: nil, duration_seconds: nil,
                     dialogue: nil, on_screen_text: nil, extra_reference_urls: [])
        @creative       = creative
        @position       = position.to_i
        @prompt         = prompt.to_s.strip
        @caption        = caption
        @duration       = duration_seconds
        @dialogue       = dialogue
        @on_screen_text = on_screen_text
        @extra_refs     = Array(extra_reference_urls).map { |u| u.to_s.strip }.reject(&:blank?)
      end

      def call
        raise Operations::Errors::Invalid, 'A nova cena precisa de uma descrição' if @prompt.blank?

        scenes = @creative.video_scenes.ordered.to_a
        if scenes.size >= PlanScenes::MAX_SCENES
          raise Operations::Errors::Invalid, "O vídeo já tem o máximo de #{PlanScenes::MAX_SCENES} cenas"
        end

        generation = @creative.generation
        pos        = @position.clamp(0, scenes.size)
        duration   = (@duration.presence || scenes.last&.duration_seconds || PlanScenes::SCENE_UNIT_SECONDS)
                     .to_i.clamp(PlanScenes::MIN_SCENE_SECONDS, PlanScenes::SCENE_UNIT_SECONDS)

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
        scene = Scenes::Create.call(
          creative: @creative, position: pos, mode: sibling_mode(scenes, generation),
          prompt: @prompt, caption: @caption, duration_seconds: duration,
          dialogue: @dialogue, on_screen_text: @on_screen_text,
          aspect_ratio: sibling&.aspect_ratio || generation&.params&.dig('aspect_ratio'),
          seed: SecureRandom.hex(6),
          reference_image_urls: base_urls + @extra_refs,
          reference_roles: base_roles + (['reference'] * @extra_refs.size)
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
