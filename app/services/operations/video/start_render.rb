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

        # The orchestrator may request GENERATED reference images (a character
        # sheet / scenario plate via Banana) to lock consistency when the user
        # gave no photo — created ONCE and attached as a typed reference to every
        # scene. Charged as image generations; a failure/broke wallet just skips it.
        generated_refs = generate_references(scene_specs.generated_references, params['aspect_ratio'])
        scenes = scene_specs.map do |spec|
          Scenes::Create.call(creative: creative, **prepend_references(spec, generated_refs))
        end
        # The video model generates NO music; the orchestrator searched an open
        # base and chose the mix — the compose step burns that track under the
        # audio. Silent videos get no music. Stored so it stays fixed unless the
        # user asks to change it (Operations::Video::ChangeMusic).
        music = silent?(params) ? {} : ResolveMusic.call(spec: scene_specs.music)
        # The locked project identity (character/wardrobe/scenario/palette/style)
        # — reapplied to every scene at render time for visual continuity.
        identity = scene_specs.identity.present? ? { 'identity' => scene_specs.identity } : {}
        # The fixed voice: ONE Cartesia voice_id for the whole video (synthesized
        # per scene at render time), so the voice never drifts between clips.
        # Silent videos get none; empty catalog degrades to model native audio.
        voice = silent?(params) ? {} : ResolveVoice.call(spec: scene_specs.voice)
        @generation.update!(params: params.merge(
          'scene_count' => scenes.size,
          'estimated_seconds' => scenes.sum { |s| s.duration_seconds.to_i }
        ).merge(identity).merge(music).merge(voice))

        # Sequential render for continuity: only the first scene starts here; each
        # completion (PollVideoSceneJob) chains the next seeded by its last frame.
        RenderScene.call(scene: scenes.first) if scenes.first
        @generation
      rescue StandardError => e
        fail_generation!(e)
        raise
      end

      private

      # Generate each requested reference (character/scenario) via Banana. Best-
      # effort: an unconfigured vendor / broke wallet / error just yields fewer
      # anchors — never blocks the video. Returns [{ url:, role: }].
      def generate_references(requests, aspect)
        Array(requests).filter_map do |req|
          Operations::Video::GenerateReference.call(
            generation: @generation, role: req['role'], prompt: req['prompt'], aspect_ratio: aspect
          )
        rescue Operations::Errors::InsufficientCredits
          Rails.logger.info('[Video::StartRender] skipping generated reference — insufficient credits')
          nil
        end
      end

      # Prepend the generated references (as the SUBJECT anchors) to a scene spec's
      # typed references, keeping the url/role arrays in sync.
      def prepend_references(spec, generated)
        return spec if generated.empty?

        spec.merge(
          reference_image_urls: generated.map { |r| r[:url] } + Array(spec[:reference_image_urls]),
          reference_roles: generated.map { |r| r[:role] } + Array(spec[:reference_roles])
        )
      end

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
