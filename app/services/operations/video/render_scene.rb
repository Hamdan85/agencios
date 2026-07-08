# frozen_string_literal: true

module Operations
  module Video
    # Submits ONE scene to OpenRouter (engine chosen by VideoConfig per mode),
    # marks it `rendering`, and enqueues the per-scene poll.
    #
    # CONTINUITY: a scene starts from the PREVIOUS scene's last frame (first-frame
    # conditioning) so the video flows without a jump-cut. A RE-RENDER of the
    # FIRST scene is conditioned on its own current opening frame instead
    # (keep-look), unless the edit asked for a restyle. The caller may pass an
    # explicit `first_frame_url` to override the derivation.
    class RenderScene < Operations::Base
      def initialize(scene:, first_frame_url: nil)
        @scene           = scene
        @first_frame_url = first_frame_url
      end

      def call
        seed = first_frame_seed
        @has_reference_media = seed.present? || @scene.reference_urls.any?
        kind = continuation_kind(seed)
        # A restyle or an intentional CUT deliberately breaks from the previous
        # frame, so a missing seed is expected there — only warn about an
        # UNINTENTIONAL continuity gap (a continuation that lost its seed).
        if seed.nil? && @scene.position.to_i.positive? && !restyle? && continues_previous?
          Rails.logger.warn("[Video::RenderScene] scene #{@scene.id} (pos #{@scene.position}) " \
                            'rendering WITHOUT a continuity seed — it will look like a new video')
        end
        # Synthesize this scene's line in the video's FIXED voice BEFORE compiling
        # the prompt, so the prompt can tell the model to lip-sync to that audio
        # AND so the scene's target length can grow to hold the whole spoken line.
        ensure_voice_clip!
        sync_target_to_audio!
        prompt = render_prompt(continuation: kind)

        job_id = begin
          submit(prompt, seed && { url: seed[:primary], frame_type: 'first' })
        rescue StandardError
          # The API/engine may reject an inline data-URL frame — retry once with
          # the public URL before giving up (continuity beats failing the render).
          raise unless seed&.dig(:fallback)

          submit(prompt, { url: seed[:fallback], frame_type: 'first' })
        end

        @scene.update!(external_id: job_id, render_state: :rendering)
        PollVideoSceneJob.perform_later(@scene.id)
        @scene
      end

      private

      def submit(prompt, frame)
        Vendors::OpenRouter::Actions::GenerateVideo.call(
          mode: @scene.mode,
          model: VideoConfig.instance.model_for(@scene.mode, quality: quality),
          prompt: prompt,
          aspect_ratio: @scene.aspect_ratio,
          # Render the SMALLEST supported clip that fits the (audio-driven) target
          # length — compose trims the shown video back to the target, so the final
          # video isn't forced to multiples of the model's fixed clip sizes.
          duration: render_clip_length,
          # Typed by media kind: video references (camera/motion guides) go as
          # video_url parts; everything else as image_url. Same order as the
          # manifest in the prompt.
          input_references: references.map do |ref|
            { url: ref[:url], type: ref[:kind] == 'vid' ? 'video_url' : 'image_url' }
          end,
          # The fixed voice as a lip-sync audio reference (empty when no voice).
          audio_references: voice_audio_references,
          # Whether the MODEL authors its own audio. We dub a fixed Cartesia voice
          # in post whenever a voice is configured, so the model must NOT add a
          # competing voice/soundtrack (generate_audio: false). Only when there is
          # NO fixed voice do we keep the model's native audio (generate_audio:
          # true). nil (legacy generations) leaves the model default.
          generate_audio: generate_audio,
          frame_images: [frame].compact
        )
      end

      # Whether the MODEL should author audio for THIS scene (the orchestrator's
      # per-scene decision, not a blanket rule):
      #   * true  — the scene needs model-generated DIEGETIC sound (sound_effects),
      #             OR it speaks and there is NO fixed voice to dub (native voice).
      #   * false — a clean/silent clip: a dubbed talking-head (voice added in post)
      #             or a scene with no audio of its own. We never let the model add
      #             music (it's a post track); the prompt states exactly what to make.
      #   * nil   — legacy generation (no audio flag): leave the model default.
      def generate_audio
        return nil if with_audio.nil?
        return false unless with_audio

        sound_effects.present? || (dialogue.present? && voice_id.blank?)
      end

      def sound_effects = @scene.metadata['sound_effects'].to_s.strip.presence
      def dialogue = @scene.metadata['dialogue'].to_s.strip.presence

      # The synthesized voice clip as an audio reference for the render (so the
      # model lip-syncs to the fixed voice). Empty when there's no voice.
      def voice_audio_references
        url = voice_url
        url.present? ? [{ url: url }] : []
      end

      def voice_url
        @voice_url ||= @scene.voice_clip_url if @scene.voice_clip.attached?
      end

      # The generation's quality tier (draft-first; 'final' after the upgrade).
      def quality
        @scene.creative.generation&.params&.fetch('quality', 'final') || 'final'
      end

      # The submitted prompt = the scene's CLEAN stored fields (visual prompt,
      # dialogue, on-screen text) compiled with the standing contracts
      # (continuity/reference manifest/style fence/audio/lettering). Compiling
      # at render time keeps chat edits covered and the stored fields lean.
      def render_prompt(continuation:)
        DecoratePrompt.call(
          prompt: @scene.prompt, mode: @scene.mode, ctx: ctx,
          continuation: continuation, with_audio: with_audio,
          dialogue: @scene.metadata['dialogue'],
          sound_effects: @scene.metadata['sound_effects'],
          on_screen_text: @scene.metadata['on_screen_text'],
          voice_tone: voice_tone,
          # When a fixed voice is synthesized for this scene, it's DUBBED in post:
          # the prompt asks for a silent talking performance (VOICE_POLICY), not
          # model-generated speech.
          voiced: voice_url.present?,
          guardrails: ctx.guardrails,
          # Hard prohibitions the chat orchestrator captured ("what CANNOT happen"),
          # merged with the client-positioning guardrails and enforced as negatives.
          render_guardrails: @scene.creative.generation&.params&.dig('render_guardrails'),
          references: references,
          identity: @scene.creative.generation&.params&.dig('identity'),
          aspect_ratio: @scene.aspect_ratio,
          # The isolated cinematography slot + the resolved engine (picks the dialect).
          camera: @scene.metadata['camera'],
          model: VideoConfig.instance.model_for(@scene.mode, quality: quality),
          # The scene is trimmed to `hold_after`; when the rendered clip is longer,
          # tell the model to HOLD the final composition after that second (create
          # nothing new past it) so the trim point is a clean, settled frame.
          target_seconds: target_seconds,
          clip_seconds: render_clip_length
        )
      end

      # The audio-driven target LENGTH of this scene (what compose trims the shown
      # video to). Starts from the planned target; when the scene speaks and its
      # synthesized voice is longer, it grows (capped at the longest supported
      # clip) so the whole line fits. Memoized.
      SPEECH_TAIL_SECONDS = 0.6
      def target_seconds
        @target_seconds ||= begin
          target = @scene.duration_seconds.to_i.clamp(PlanScenes::MIN_SCENE_SECONDS,
                                                      VideoConfig.instance.clip_seconds_for(@scene.mode).max)
          vs = @scene.metadata['voice_seconds'].to_f
          if with_audio && vs.positive?
            needed  = (vs + SPEECH_TAIL_SECONDS).ceil
            max_clip = VideoConfig.instance.clip_seconds_for(@scene.mode).max
            target = needed.clamp(target, max_clip)
          end
          target
        end
      end

      # The clip length actually submitted to the model — the smallest supported
      # length that fits the target, EXCEPT when the engine forces a fixed length
      # because a reference/seed frame is attached (Veo locks to 8s with reference
      # images). Compose trims the shown scene back to the target regardless.
      def render_clip_length
        @render_clip_length ||= VideoConfig.instance.render_clip_length(
          target_seconds, quality: quality, has_reference_media: @has_reference_media
        )
      end

      # Persist the audio-grown target back onto the scene so compose trims to it,
      # the timeline shows it and billing reflects it. Only writes when it changed.
      def sync_target_to_audio!
        return if target_seconds == @scene.duration_seconds.to_i

        @scene.update!(duration_seconds: target_seconds)
      rescue StandardError => e
        Rails.logger.warn("[Video::RenderScene] could not sync target for scene #{@scene.id}: #{e.message}")
      end

      # Ensure this scene's spoken line is synthesized in the video's FIXED voice
      # (Cartesia), cached by a (voice_id + dialogue) fingerprint so a re-render
      # only re-synthesizes when the line or the voice changed. Best-effort: a
      # missing/failed synthesis leaves no clip → the render falls back to the
      # model's native audio (never fails the render). Skipped on silent videos,
      # scenes with no dialogue, or when no voice_id is configured.
      def ensure_voice_clip!
        line = @scene.metadata['dialogue'].to_s.strip
        return if !with_audio || line.blank? || voice_id.blank?

        fingerprint = Digest::SHA256.hexdigest("#{voice_id}|#{@scene.creative.generation&.params&.dig('voice_speed')}|#{line}")
        return if @scene.voice_clip.attached? && @scene.metadata['voice_fingerprint'] == fingerprint

        audio = Vendors::Cartesia::Actions::Synthesize.call(
          text: line, voice_id: voice_id, language: VideoConfig::VOICE_LANGUAGE,
          speed: @scene.creative.generation&.params&.dig('voice_speed')
        )
        return if audio.nil?

        @scene.voice_clip.attach(io: StringIO.new(audio[:bytes]), filename: "voice-#{@scene.id}.mp3",
                                 content_type: audio[:content_type])
        # Measure the spoken line so the scene's target length can grow to hold it
        # (audio-orchestrated pacing) and compose can fit the voice in sync.
        seconds = Vendors::Ffmpeg::Duration.call(bytes: audio[:bytes], ext: '.mp3')
        @scene.update!(metadata: @scene.metadata.merge(
          'voice_fingerprint' => fingerprint,
          'voice_seconds' => (seconds.positive? ? seconds.round(2) : nil)
        ).compact)

        # Record the real Cartesia voice cost (per character) in the unified ledger
        # so it enters the cost-plus credit charge. Best-effort — never raises.
        gen = @scene.creative.generation
        Operations::Ai::LogUsage.call(
          provider: AiUsageLog::PROVIDER_CARTESIA, operation: 'synthesize_voice',
          model: voice_id, units: line.length, unit_kind: AiUsageLog::UNIT_CHARACTER,
          subject: @scene.creative, workspace: @scene.workspace, user: gen&.user
        )
      rescue StandardError => e
        Rails.logger.warn("[Video::RenderScene] voice synth failed for scene #{@scene.id}: #{e.class}: #{e.message}")
      end

      def voice_id = @scene.creative.generation&.params&.dig('voice_id').to_s.strip.presence

      # The scene's typed references (identifier + role + kind, stored order) —
      # the ONE list that feeds both the submitted inputs and the prompt
      # manifest, so they can never desync. Memoized: submit may run twice
      # (data-URL seed fallback).
      def references
        @references ||= @scene.labeled_references
      end

      # The requested vocal delivery (avatar mode) → a delivery tone the model
      # applies to the spoken line. nil when no voice was chosen or sound is off.
      VOICE_TONES = {
        'pt_br_warm' => 'warm and friendly', 'pt_br_energetic' => 'energetic and upbeat',
        'pt_br_pro' => 'professional and confident'
      }.freeze

      def voice_tone
        return nil unless with_audio

        VOICE_TONES[@scene.creative.generation&.params&.dig('voice').to_s]
      end

      def restyle? = @scene.metadata['restyle'] == true

      # A scene continues the previous shot (seamless, seeded) unless the
      # storyboard marked it a CUT. Legacy scenes (nil) default to continue.
      def continues_previous? = @scene.metadata['continues_previous'] != false

      # What continuity directive the compiled prompt gets:
      #   :self   — a keep-look re-render seeded by the scene's own frame
      #   :previous — a seamless continuation seeded by the predecessor's frame
      #   :cut    — an intentional NEW shot (same world/characters, no seed)
      #   false   — the first scene, or an unseeded standalone
      def continuation_kind(seed)
        return seed[:kind] if seed
        return :cut if @scene.position.to_i.positive? && !restyle? && !continues_previous?

        false
      end

      # nil when the generation predates the flag — DecoratePrompt then skips
      # the audio directive.
      def with_audio
        params = @scene.creative.generation&.params
        return nil if params.nil? || !params.key?('with_audio')

        ActiveModel::Type::Boolean.new.cast(params['with_audio'])
      end

      # Same context shape StartRender plans with, rebuilt from the records (this
      # runs in jobs — never from Current). Memoized: several compile steps read it.
      def ctx
        @ctx ||= begin
          creative  = @scene.creative
          client_id = creative.generation&.params&.dig('client_id')
          ::Tickets::CreativeContext.for(
            creative.ticket,
            creative_type: creative.creative_type,
            client: client_id.present? ? @scene.workspace.clients.find_by(id: client_id) : nil
          )
        end
      end

      # The CONTINUITY SEED — the previous scene's final frame, the one thing
      # that makes scenes continue instead of coming out as N versions of the
      # same video. The frame is inlined as a data URL so the engine ALWAYS
      # receives the actual pixels: a public URL depends on the app host being
      # reachable from OpenRouter (rotated ngrok tunnels / interstitials break
      # conditioning silently). The public URL rides along as fallback.
      # Returns { primary:, fallback: } or nil (first scene / frame missing).
      MAX_INLINE_FRAME_BYTES = 4.megabytes

      def first_frame_seed
        return { primary: @first_frame_url, kind: :previous } if @first_frame_url.present?
        # A restyle breaks from the current look at ANY position — no seed and no
        # continuity directive, so the new look isn't fought by the old frame.
        return nil if restyle?
        # A CUT is a new shot in the same video — it must NOT start from the
        # previous frame (the scenario/framing differs), only the input_references
        # (the things used) carry over.
        return nil if @scene.position.to_i.positive? && !continues_previous?
        return own_first_frame_seed if @scene.position.to_i.zero?

        prev = @scene.creative.video_scenes.find_by(position: @scene.position - 1)
        frame = prev&.last_frame
        return nil unless frame&.attached?

        url = prev.last_frame_url
        return url.presence && { primary: url, kind: :previous } if frame.byte_size.to_i > MAX_INLINE_FRAME_BYTES

        data = "data:#{frame.content_type.presence || 'image/png'};base64,#{Base64.strict_encode64(frame.download)}"
        { primary: data, fallback: url.presence, kind: :previous }.compact
      rescue StandardError => e
        Rails.logger.warn("[Video::RenderScene] seed frame unavailable for scene #{@scene.id}: #{e.class}: #{e.message}")
        nil
      end

      # A RE-RENDER of the first scene keeps the look the user already saw by
      # conditioning on its own current opening frame — the "reference to the
      # last video". Skipped when the edit asked for a restyle (metadata) or the
      # scene never rendered. Scenes 2+ get keep-look for free from the chain.
      def own_first_frame_seed
        return nil unless @scene.clip.attached?

        data = nil
        @scene.clip.open do |clip|
          png = "#{clip.path}.first.png"
          Vendors::Ffmpeg::FirstFrame.call(input_path: clip.path, output_path: png)
          bytes = File.binread(png)
          File.delete(png) if File.exist?(png)
          break if bytes.bytesize > MAX_INLINE_FRAME_BYTES

          data = "data:image/png;base64,#{Base64.strict_encode64(bytes)}"
        end
        data && { primary: data, kind: :self }
      rescue StandardError => e
        Rails.logger.warn("[Video::RenderScene] own first-frame extract failed for scene #{@scene.id}: #{e.message}")
        nil
      end
    end
  end
end
