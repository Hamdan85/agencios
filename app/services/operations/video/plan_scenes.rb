# frozen_string_literal: true

module Operations
  module Video
    # Splits a video brief into an ordered list of SCENE specs (prompt + caption +
    # duration + seed) — the unit of independent render + edit.
    #
    # THE REQUESTED DURATION IS A HARD SCENE BUDGET. Each scene renders as one
    # model clip of ~SCENE_UNIT_SECONDS (video models return ~8s clips regardless
    # of shorter asks), so an 8s request is exactly ONE scene — never three scenes
    # that balloon into a 24s video billed at 3x.
    #
    # The scene breakdown is AI-planned (Prompts::VideoStoryboard) so the video
    # gets the RIGHT number of meaningful scenes within the budget — never filler.
    # It falls back to a deterministic beat structure when the AI is unavailable
    # (offline / no key), so generation always works and stays testable:
    #   * avatar  — the script's sentences distributed across the budgeted scenes
    #   * product — a hook → feature → CTA beat structure from the brief
    #
    # Scene prompts are stored CLEAN: the standing directives (continuity, brand,
    # legible-text) are appended at render time by Operations::Video::DecoratePrompt,
    # so chat edits keep them and the agent context stays lean. Scenes render
    # sequentially and continue from each other's last frame — see RenderScene.
    class PlanScenes < Operations::Base
      # The scene specs PLUS the video-level decisions the orchestrator made: the
      # locked IDENTITY (character/wardrobe/scenario/palette/style), the MUSIC
      # spec, and the VOICE pick (one fixed voice for the whole video). Acts as a
      # plain Array (callers `.map`/`.size`/`.first` it) with extra readers.
      class Plan < Array
        attr_accessor :identity, :music, :voice, :generated_references, :constraints
      end

      MAX_SCENES = 6
      MIN_SCENE_SECONDS = 4
      # One scene ≈ one model clip. Veo/Seedance render ~8s per submission, so the
      # scene count must be derived from the requested duration, not invented.
      SCENE_UNIT_SECONDS = 8
      # Generous ceiling so the storyboard keeps ALL the brief's concrete details
      # (named characters, must-shows, exact lines) instead of truncating them.
      STORYBOARD_MAX_TOKENS = 4000

      PRODUCT_BEATS = [
        { key: 'hook',    caption: 'Abertura que prende a atenção', hint: 'attention-grabbing opening shot of the product' },
        { key: 'feature', caption: 'Produto em destaque',          hint: 'the product in dynamic close-up, hero framing' },
        { key: 'cta',     caption: 'Chamada para ação',            hint: 'closing call-to-action beat' }
      ].freeze

      def initialize(ctx:, mode:, script: nil, brief: nil, total_duration:, aspect_ratio:,
                     reference_image_urls: [], reference_descriptions: {}, with_audio: nil)
        @ctx    = ctx
        @mode   = mode.to_s
        # { url => "user's words for the file" } — carried into the typed manifest.
        @ref_descriptions = (reference_descriptions || {}).to_h
        # The caller's typed params win; but ticket/autopilot flows pass none —
        # fall back to the ticket's scope so the storyboard is built from the
        # planned content (script/brief/topic), never from brand context alone.
        @script = script.presence || ctx.script
        @brief  = brief.presence || ctx.copy_brief.presence || ctx.brief.presence || ctx.topic
        @total  = total_duration.to_i
        @aspect = aspect_ratio
        @refs   = Array(reference_image_urls)
        @with_audio = with_audio
      end

      def call
        beats = ai_beats.presence || deterministic_beats
        beats = beats.first(max_scenes)
        beats = [fallback_beat] if beats.empty?
        # The orchestrator may keep the user's mode or switch to a better fit
        # (@ai_mode set in ai_beats); that drives the ENGINE. The reference SET
        # (roles + identifiers) stays the one the storyboard was shown and cited
        # (built from @mode) — rebuilding it for a switched mode would rename or
        # drop assets the scene prompts already reference by identifier.
        mode  = effective_mode
        refs  = media_references
        # The even split — a flexible TARGET length (clamped, NOT snapped to a
        # discrete clip length): the render picks the smallest supported clip that
        # fits and compose TRIMS the shown video back to this target, so the final
        # length isn't forced to multiples of the model's fixed clip sizes.
        even  = clamp_target(scene_duration(beats.size), mode)

        specs = beats.each_with_index.map do |beat, i|
          {
            position: i,
            mode: mode,
            prompt: beat[:prompt],
            camera: beat[:camera],
            caption: beat[:caption].to_s[0, 90],
            dialogue: beat[:dialogue],
            sound_effects: beat[:sound_effects],
            on_screen_text: beat[:on_screen_text],
            # The storyboard PACES each shot by its intended length (sized to the
            # spoken line when there is speech); the render clip snaps up and the
            # compose trims to this exact target.
            duration_seconds: clamp_target(beat[:duration_seconds], mode) || even,
            # Scene 1 always establishes; later scenes CONTINUE the previous shot
            # (seamless, seeded by its last frame) UNLESS the storyboard marked a
            # CUT — a new shot with the same characters/world but a fresh framing,
            # which must NOT start from the previous frame.
            continues_previous: i.positive? && beat.fetch(:continues_previous, true),
            aspect_ratio: @aspect,
            seed: SecureRandom.hex(6),
            reference_image_urls: refs.map { |r| r[:url] },
            reference_roles: refs.map { |r| r[:role] },
            reference_descriptions: refs.map { |r| r[:description] }
          }
        end
        specs = cap_to_total(specs)

        # Guarantee the locked identity's recurring CHARACTER / signature SCENARIO
        # get a GENERATED anchor image before the first render when the user gave
        # no photo of them — the storyboard only requests these sometimes, so
        # without this the look rests on the text alone and drifts between scenes.
        @generated_references = ensure_identity_anchors(@generated_references, refs, mode)

        Plan[*specs].tap do |plan|
          plan.identity = @identity
          plan.music = @music
          plan.voice = @voice
          plan.generated_references = @generated_references
          plan.constraints = @constraints
        end
      end

      private

      # How many CLIPS (scenes) the total can hold — FLOOR of total/min-clip so the
      # scenes' durations SUM to ~the total, never overshoot it (a 4–6s video is
      # ONE clip, not two 4s clips = 8s). The storyboard still uses the fewest it
      # needs; sub-clip cuts for a very short video are described in the prompt.
      def max_scenes
        (@total / MIN_SCENE_SECONDS.to_f).floor.clamp(1, MAX_SCENES)
      end

      # Keep scenes only until their durations FILL the requested total, so a
      # storyboard that over-paces (e.g. two 8s clips for an 8s video) never
      # balloons the length/cost. Always keeps at least the first scene; the last
      # kept scene may overshoot by less than one clip. Reindexes positions +
      # resets the new scene 1 to establish (no seed from a dropped predecessor).
      def cap_to_total(specs)
        return specs if specs.size <= 1

        acc = 0
        kept = specs.take_while do |s|
          fill = acc < @total
          acc += s[:duration_seconds].to_i
          fill
        end
        kept = specs.first(1) if kept.empty?
        kept.each_with_index { |s, i| s[:position] = i; s[:continues_previous] = false if i.zero? }
        kept
      end

      # The DETERMINISTIC fallback stays conservative (one ~8s clip per beat) — it
      # is the offline path, not a place to invent cutscenes.
      def deterministic_scenes
        (@total / SCENE_UNIT_SECONDS.to_f).ceil.clamp(1, MAX_SCENES)
      end

      # Even split of the requested total across the scenes, clamped to one clip
      # (snapped to a supported length by the caller).
      def scene_duration(count)
        (@total.to_f / count).round.clamp(MIN_SCENE_SECONDS, SCENE_UNIT_SECONDS)
      end

      # Snap a storyboard-provided per-scene duration to the NEAREST clip length
      # the given mode's engine actually supports (never an arbitrary value); nil
      # when absent (caller falls back to the even split).
      def snap_seconds(value, mode)
        return nil unless value.to_i.positive?

        VideoConfig.instance.snap_seconds(value, mode)
      end

      # Clamp a per-scene TARGET length to [MIN_SCENE_SECONDS, longest supported
      # clip] WITHOUT snapping to the discrete clip set — the render renders a
      # supported clip >= this and compose trims back to it, so the shown length
      # can be any value in range (audio-driven), not a fixed clip multiple. nil
      # when absent (caller uses the even split).
      def clamp_target(value, mode)
        secs = value.to_i
        return nil unless secs.positive?

        max_clip = VideoConfig.instance.clip_seconds_for(mode).max
        secs.clamp(MIN_SCENE_SECONDS, max_clip)
      end

      # --- AI-planned storyboard (preferred) ------------------------------------
      def ai_beats
        storyboard = Prompts::VideoStoryboard.new(
          workspace: @ctx.workspace, client: @ctx.client, mode: @mode,
          brief: @brief, script: @script, total_duration: @total,
          aspect_ratio: @aspect, max_scenes: max_scenes, with_audio: @with_audio,
          # The clip lengths the seeded mode's engine supports — the storyboard
          # picks each scene's duration AMONG these, not an arbitrary value.
          clip_seconds: VideoConfig.instance.clip_seconds_for(@mode),
          # The full planning direction — what the video must SAY/SHOW/AVOID.
          objective: @ctx.objective, persona: @ctx.persona,
          content_pillar: @ctx.content_pillar, production_scope: @ctx.production_scope,
          positioning_brief: @ctx.positioning_brief, references: @ctx.references.presence&.join('; '),
          has_references: @refs.any?,
          # The typed media references the renderer will receive (identifier +
          # role) — the SAME set the final specs use, so every identifier the
          # storyboard cites resolves in the render manifest.
          media_references: media_references,
          # The fixed-voice options the director may pick ONE from (LIVE from the
          # Cartesia library + admin overrides) — so it matches the voice to the
          # character. Empty ⇒ no external voice (model native audio).
          voices: Operations::Video::VoiceOptions.list
        )
        client = Vendors::Ai.client(model: Vendors::Ai.model_for('video_storyboard'))
        result = client.generate(
          system: storyboard.system,
          prompt: "#{storyboard.brief_context}\n\nBuild the storyboard now by calling the tool.",
          tool: Prompts::VideoStoryboard.storyboard_tool,
          max_tokens: STORYBOARD_MAX_TOKENS
        )
        tool = result.tool_input.is_a?(Hash) ? result.tool_input : {}
        # The orchestrator may set the video MODE (keep the user's or switch).
        @ai_mode = tool['mode'].to_s if VideoConfig::MODES.include?(tool['mode'].to_s)
        # The orchestrator's LOCKED identity — the look every scene shares.
        @identity = clean_identity(tool['identity'])
        # The orchestrator's music spec: the search query + the ffmpeg mix params
        # (one track per video, burned in post). Kept only when it has a query/mood.
        m = tool['music']
        @music = m if m.is_a?(Hash) && (m['query'].present? || m['mood'].present?)
        # The orchestrator's VOICE pick — ONE fixed voice for the whole video
        # (a catalog label or voice_id). Kept only when non-blank.
        v = tool['voice']
        @voice = { 'voice' => v.to_s } if v.is_a?(String) && v.strip.present?
        # HARD prohibitions the director gathered — enforced as negative constraints
        # on every scene at render (merged with the client-positioning guardrails).
        @constraints = Array(tool['constraints']).map { |c| c.to_s.strip }.reject(&:blank?).uniq.presence
        # The orchestrator's request to GENERATE reference images (character sheet
        # / scenario) for consistency — each { role, prompt }, kept only when the
        # prompt is present. Charged as image generations at render time.
        @generated_references = clean_generated_references(tool['generated_references'])
        scenes = tool['scenes']
        Array(scenes).filter_map do |s|
          prompt = s['prompt'].to_s.strip
          next if prompt.blank?

          {
            prompt: prompt,
            camera: s['camera'].to_s.strip.presence,
            caption: s['caption'].to_s.strip.presence || prompt[0, 90],
            dialogue: s['dialogue'].to_s.strip.presence,
            sound_effects: s['sound_effects'].to_s.strip.presence,
            on_screen_text: s['on_screen_text'].to_s.strip.presence,
            duration_seconds: s['duration_seconds'],
            # Default to a seamless continuation; only an explicit false is a cut.
            continues_previous: s['continues_previous'] != false
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[Video::PlanScenes] storyboard AI failed, using fallback: #{e.class}: #{e.message}")
        nil
      end

      # Keep only well-formed generated-reference requests: a valid role + a
      # non-blank prompt. Capped so a runaway plan can't spend on many images —
      # but generous enough to hold ONE reference PER recurring character (a video
      # may have several people/characters) plus a signature scenario.
      GENERATED_REFERENCE_ROLES = %w[character scene].freeze
      MAX_GENERATED_REFERENCES = 4
      def clean_generated_references(value)
        Array(value).filter_map do |r|
          h = r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : (r.respond_to?(:to_h) ? r.to_h : {})
          h = h.stringify_keys
          role   = GENERATED_REFERENCE_ROLES.include?(h['role'].to_s) ? h['role'].to_s : 'character'
          prompt = h['prompt'].to_s.strip
          next if prompt.blank?

          { 'role' => role, 'prompt' => prompt }
        end.first(MAX_GENERATED_REFERENCES)
      end

      # Add a deterministic character/scenario anchor to the model's requests when
      # the locked identity defines one and NO reference photo of it exists — so the
      # anchor is always generated up front, not left to the model's discretion.
      # Merges (one per role), capped like the model path.
      #   character — only when the video has a recurring character (has_character)
      #     and no face photo is attached (avatar) or character reference.
      #   scene     — a signature setting with no location photo; skipped for avatar
      #     UGC, where the selfie background is incidental.
      def ensure_identity_anchors(requested, refs, mode)
        out = Array(requested).dup
        return out unless @identity.is_a?(Hash)

        have   = out.map { |r| r['role'] }
        photos = Array(refs).map { |r| r[:role].to_s }

        if @identity['has_character'] && @identity['character'].present? &&
           have.exclude?('character') && (photos & %w[character avatar]).empty?
          out << { 'role' => 'character', 'prompt' => @identity['character'].to_s.strip }
        end
        if @identity['scenario'].present? && mode.to_s != 'avatar' &&
           have.exclude?('scene') && photos.exclude?('scene')
          out << { 'role' => 'scene', 'prompt' => @identity['scenario'].to_s.strip }
        end
        out.first(MAX_GENERATED_REFERENCES)
      end

      # Keep only the known identity fields (trimmed); has_character is boolean.
      IDENTITY_TEXT_KEYS = %w[character wardrobe scenario palette style].freeze
      def clean_identity(value)
        return nil unless value.is_a?(Hash)

        out = {}
        out['has_character'] = ActiveModel::Type::Boolean.new.cast(value['has_character']) if value.key?('has_character')
        IDENTITY_TEXT_KEYS.each { |k| out[k] = value[k].to_s.strip.presence }
        out.compact!
        out.presence
      end

      # --- deterministic fallback ----------------------------------------------
      def deterministic_beats
        @mode == 'avatar' ? avatar_beats : product_beats
      end

      # The whole script still gets delivered: sentences are grouped into the
      # budgeted scenes instead of one scene per sentence — the spoken line is a
      # FIRST-CLASS field (dialogue), never buried inside the visual prompt.
      # Scene 1 establishes; later scenes CONTINUE the same take.
      def avatar_beats
        script = (@script.presence || @brief.presence || @ctx.topic).to_s
        sentences = script.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
        sentences = [script] if sentences.empty?
        per_scene = (sentences.size.to_f / deterministic_scenes).ceil
        sentences.each_slice(per_scene).each_with_index.map do |group, i|
          line = group.join(' ')
          prompt = if i.zero?
                     'Authentic UGC talking-head, casual first-person selfie framing, natural ' \
                       'lighting. A creator speaks directly to camera, warm and confident'
                   else
                     'The SAME creator, same take and framing, keeps talking to camera — ' \
                       'continuing seamlessly, no reset'
                   end
          { caption: line[0, 90], prompt: prompt, dialogue: line }
        end
      end

      # Beats chain forward: only scene 1 states the subject; later beats advance
      # the SAME shot — restating the whole brief per scene renders N versions of
      # the same video instead of one continuous story.
      def product_beats
        subject = (@brief.presence || @ctx.topic).to_s
        PRODUCT_BEATS.first(deterministic_scenes.clamp(1, PRODUCT_BEATS.size)).each_with_index.map do |beat, i|
          prompt = if i.zero?
                     "Short vertical product video, #{beat[:hint]}. Subject: #{subject}. " \
                       'Feature the product from the reference photos faithfully — keep its exact ' \
                       'shape, colors and label; do not distort or restyle it. Dynamic, scroll-stopping motion'
                   else
                     "The SAME product video continues — next beat: #{beat[:hint]}. Keep the exact " \
                       'same product, setting, lighting and look; advance the action forward, never ' \
                       'restart or re-establish the shot'
                   end
          { caption: beat[:caption], prompt: prompt }
        end
      end

      def fallback_beat
        { prompt: @ctx.topic.to_s, caption: @ctx.topic.to_s[0, 90] }
      end

      # The mode the render uses: the orchestrator's choice, else the requested.
      def effective_mode
        @ai_mode.presence || @mode
      end

      # The ONE typed reference set for this plan — built from the USER's mode
      # and reused by both the storyboard (which cites the identifiers) and the
      # final specs (which persist them), so the identifiers never diverge even
      # when the orchestrator switches the engine mode. Memoized.
      def media_references
        @media_references ||= scene_references(@mode)
      end

      # The visual-identity references handed to the render, per mode — built
      # through Operations::Video::References so every entry gets a typed ROLE, a
      # media KIND and a stable IDENTIFIER (img_product_v1, vid_camera_ref_v1…),
      # priority-sorted (subject first, logo last). The urls + roles are persisted
      # on the scene in this order, so the manifest never re-derives a role by
      # URL equality against a (possibly changed) brand asset at render time.
      #   product — the user's product photos + the brand logo (mark fidelity)
      #   avatar  — the creator avatar (spokesperson's face) + attached refs
      #   character/scene/motion — only the user's attached refs (style/subject),
      #     no forced avatar/logo (the character is described, not a real face)
      def scene_references(mode)
        raw =
          case mode
          when 'product'
            @refs.map { |url| { url: url, role: 'product', description: @ref_descriptions[url] } } +
              [{ url: @ctx.brand_logo_url, role: 'logo' }]
          when 'avatar'
            [{ url: @ctx.brand_avatar_url, role: 'avatar' }] +
              @refs.map { |url| { url: url, role: 'reference', description: @ref_descriptions[url] } }
          else # character / scene / motion — user references only
            @refs.map { |url| { url: url, role: 'reference', description: @ref_descriptions[url] } }
          end
        References.build(raw)
      end
    end
  end
end
