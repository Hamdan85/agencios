# frozen_string_literal: true

module Operations
  module Video
    # The SLOW half of a video generation, run from StartVideoRenderJob (never
    # in-request): plans the storyboard (AI call — tens of seconds), creates the
    # scenes, and submits the first render (the poll chain advances the rest with
    # frame continuity). On failure it refunds the held credits and fails the
    # generation + creative, broadcasting so the UI settles instead of spinning.
    class StartRender < Operations::Base
      def initialize(generation:)
        @generation = generation
      end

      def call
        return @generation unless @generation.status_processing?

        creative = @generation.creative
        # Idempotent: a retried job must not duplicate scenes.
        return @generation if creative.nil? || creative.video_scenes.exists?

        params = @generation.params || {}
        ctx = ::Tickets::CreativeContext.for(
          creative.ticket,
          creative_type: creative.creative_type,
          client: @generation.workspace.clients.find_by(id: params['client_id'])
        )

        scene_specs = PlanScenes.call(
          ctx: ctx, mode: params['mode'], script: params['script'], brief: params['brief'],
          total_duration: params['duration'].to_i, aspect_ratio: params['aspect_ratio'],
          reference_image_urls: Array(params['reference_image_urls']),
          with_audio: params.key?('with_audio') ? ActiveModel::Type::Boolean.new.cast(params['with_audio']) : nil
        )

        scenes = scene_specs.map { |spec| Scenes::Create.call(creative: creative, **spec) }
        # The video model generates NO music; the orchestrator searched an open
        # base and chose the mix — the compose step burns that track under the
        # audio. Silent videos get no music. Stored so it stays fixed unless the
        # user asks to change it (Operations::Video::ChangeMusic).
        music = silent?(params) ? {} : ResolveMusic.call(spec: scene_specs.music)
        @generation.update!(params: params.merge(
          'scene_count' => scenes.size,
          'estimated_seconds' => scenes.sum { |s| s.duration_seconds.to_i }
        ).merge(music))

        # Sequential render for continuity: only the first scene starts here; each
        # completion (PollVideoSceneJob) chains the next seeded by its last frame.
        RenderScene.call(scene: scenes.first) if scenes.first
        @generation
      rescue StandardError => e
        fail_generation!(e)
        raise
      end

      private

      def silent?(params)
        params.key?('with_audio') && ActiveModel::Type::Boolean.new.cast(params['with_audio']) == false
      end

      def fail_generation!(error)
        Operations::Credits::Refund.call(generation: @generation)
        @generation.update!(status: :failed, failure_reason: error.message.to_s[0, 480])
        @generation.creative&.update!(status: :failed)
        ActionCable.server.broadcast("generations_#{@generation.workspace_id}",
                                     { event: 'generation_progress', id: @generation.id,
                                       kind: 'video', status: 'failed' })
      rescue StandardError
        nil
      end
    end
  end
end
