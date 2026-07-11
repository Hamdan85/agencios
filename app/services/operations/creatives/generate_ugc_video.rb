# frozen_string_literal: true

module Operations
  module Creatives
    # Kicks off a video render through OpenRouter (the video seam). Two modes:
    #   * avatar  — a talking-head reading the script (native audio)
    #   * product — a short product clip built from reference photos
    #
    # A video is a SEQUENCE OF SCENES: the brief is planned into scenes
    # (Operations::Video::PlanScenes), each rendered independently so a later edit
    # re-renders one scene, not the whole video. When every scene is ready,
    # Operations::Video::Compose ffmpeg-concats them into the final Creative.
    #
    # This operation is the FAST, in-request half: it validates, creates the
    # creative + generation, holds the credit estimate, and hands off to
    # StartVideoRenderJob — the storyboard AI call and the vendor submits are
    # slow (tens of seconds) and NEVER run in-request. The UI gets the generation
    # back immediately and follows progress via polling/broadcasts.
    #
    # The ENGINE is never chosen by the caller: VideoConfig maps each mode to the
    # best cost/benefit model (admin-editable, no deploy). Credits are held up
    # front for the requested duration and reconciled to the real duration on
    # compose. Raises InsufficientCredits (402) before anything is created.
    class GenerateUgcVideo < Operations::Base
      PROVIDER = 'openrouter'
      MODES = VideoConfig::MODES

      # creative: an EXISTING draft creative to launch (the chat interview built
      # its context before deciding to generate) — reused instead of creating a
      # new one, so the interview chat/history stays on it. Nil ⇒ create fresh
      # (immediate generation: autopilot / ticket flows).
      def initialize(ticket: nil, mode: nil, script: nil, prompt: nil, avatar: nil, voice: nil,
                     aspect_ratio: nil, duration: nil, reference_image_urls: [],
                     reference_descriptions: {}, creative_type: nil, client_id: nil,
                     with_audio: nil, creative: nil)
        @ticket        = ticket
        @creative_arg  = creative
        @script        = script
        @prompt        = prompt
        @voice         = voice
        @aspect_ratio  = aspect_ratio
        @duration      = duration
        @ref_urls      = Array(reference_image_urls).map { |u| u.to_s.strip }.reject(&:blank?)
        # { url => "what the user says this file is" } — persisted on the generation
        # so the storyboard/render manifest uses each reference the way it was meant.
        @ref_descriptions = (reference_descriptions || {}).to_h.select { |u, _| @ref_urls.include?(u.to_s) }
        # The type is no longer a mandatory upfront pick — the creation form sends
        # no mode; the storyboard DIRECTOR chooses the real one (avatar/product/
        # character/scene/motion). This is only the SEED: honor an explicit mode,
        # else lean on the attached references (photos ⇒ product) and default to
        # avatar. Reference roles at plan time follow this seed; the director's
        # switch drives the actual scene engines.
        @mode          = MODES.include?(mode.to_s) ? mode.to_s : (@ref_urls.any? ? 'product' : 'avatar')
        @creative_type = creative_type
        @client_id     = client_id
        @with_audio    = with_audio.nil? ? true : ActiveModel::Type::Boolean.new.cast(with_audio)
      end

      def call
        client = resolve_client
        ctx = ::Tickets::CreativeContext.for(@ticket, creative_type: type, client: client)
        ensure_client_active!(ctx.client)

        aspect   = @aspect_ratio.presence || ctx.aspect_ratio.presence || '9:16'
        duration = clamp_duration(@duration)

        # Videos render DRAFT-FIRST (fast/cheap preview model): the user iterates
        # in the editor and upgrades to the final model on approval. Reuse the
        # interview's draft creative when given (keeps its chat history); else
        # create a fresh one (immediate generation).
        video_meta = { mode: @mode, aspect_ratio: aspect, duration: duration,
                       with_audio: @with_audio, quality: 'draft' }
        creative =
          if @creative_arg
            # Leave the interview phase and move into generation.
            @creative_arg.update!(status: :generating,
                                  metadata: (@creative_arg.metadata || {}).merge(video_meta.stringify_keys).except('phase', 'intake'))
            @creative_arg
          else
            Operations::Creatives::Create.call(
              ticket: @ticket, client: ctx.client, creative_type: ctx.creative_type || type,
              source: :generated, status: :generating, provider: PROVIDER, metadata: video_meta
            )
          end

        generation = workspace.generations.create!(
          user: Current.user, creative: creative, kind: :video, status: :processing, provider: PROVIDER,
          params: { mode: @mode, aspect_ratio: aspect, duration: duration,
                    script: @script, brief: @prompt, client_id: client&.id,
                    voice: @voice, reference_image_urls: @ref_urls,
                    reference_descriptions: @ref_descriptions, with_audio: @with_audio,
                    quality: 'draft', estimated_seconds: duration }
        )

        # Hold a credit estimate for the requested duration BEFORE the paid render.
        # Compose reconciles to the real total. Raises InsufficientCredits (402).
        estimate_desc = I18n.with_locale(workspace_locale(workspace)) { I18n.t('operations.creatives.video_estimate') }
        Operations::Credits::Debit.call(
          workspace: workspace,
          amount: Pricing.credits_for(kind: :video, seconds: duration),
          generation: generation, description: estimate_desc
        )

        # The slow half (storyboard AI + vendor submit) runs off-request.
        StartVideoRenderJob.perform_later(generation.id)

        broadcast(event: 'generation_progress', id: generation.id, kind: 'video', status: 'processing')
        generation
      end

      private

      def type
        @creative_type.presence || @ticket&.creative_type.presence || 'ugc_video'
      end

      def resolve_client
        return nil if @client_id.blank?

        workspace.clients.find_by(id: @client_id)
      end

      def workspace_locale(ws)
        I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
      end

      def clamp_duration(seconds)
        max = VideoConfig.instance.max_duration
        secs = (seconds.presence || Pricing::DEFAULT_VIDEO_SECONDS).to_i
        secs.clamp(1, max)
      end

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
