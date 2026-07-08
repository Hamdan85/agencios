# frozen_string_literal: true

module Operations
  module Video
    # Compiles the FINAL prompt submitted to the video model for one scene — the
    # single place where every piece of available context meets:
    #
    #   * the scene's VISUAL prompt (what the storyboard/agent wrote — clean)
    #   * the exact DIALOGUE and ON-SCREEN TEXT (first-class fields, quoted)
    #   * the continuity contract (previous-frame chain or keep-look re-render)
    #   * a positional manifest of the reference images (product / logo / avatar)
    #   * the brand + production direction, FENCED as style context
    #   * the audio and lettering contracts
    #
    # Shape is deliberate: the scene paragraph comes FIRST (models weight the
    # opening most), then one constraint per line — sentence-gluing buried the
    # contracts and let models treat context as content. Everything here is
    # deterministic; the AI agents only ever produce the creative fields.
    class DecoratePrompt < Operations::Base
      # Scenes 2+ must READ as the same video, not a different clip: the render
      # is seeded with the previous scene's final frame, and the prompt says so.
      # "Next beat" is the key: without it, models re-establish the concept and
      # every scene comes out as another VERSION of the same video.
      CONTINUITY_DIRECTIVE =
        'This scene is the NEXT BEAT of an ongoing video, not a new video: the provided ' \
        'first-frame image IS the previous scene\'s final frame — pick up from it ' \
        'seamlessly and CONTINUE the action forward. Keep the SAME world, subject, ' \
        'framing style, lighting and color grade. Never restart, re-establish or retake ' \
        'the concept; no cut, no scene reset, no new location. If the shot widens or ' \
        'pulls back to reveal more of the cast/scene, those elements ALREADY EXIST in ' \
        'the world and must come into frame NATURALLY through the camera move — never ' \
        'let characters or objects POP/APPEAR out of nowhere.'

      # A KEEP-LOOK re-render: the seed is the scene's own current opening frame.
      SELF_CONTINUITY_DIRECTIVE =
        'The provided first-frame image is this scene\'s CURRENT look — keep the SAME ' \
        'world, subject, framing, lighting and color grade, and apply ONLY the changes ' \
        'this prompt describes. Do not reinvent the scene.'

      # A CUT: a new shot in the SAME video (no seed frame). Same characters and
      # brand world, fresh framing/scenario — so it must NOT be a hard restart of
      # a different-looking video.
      CUT_DIRECTIVE =
        'This is a CUT to a NEW shot within the SAME video: keep the SAME characters, ' \
        'wardrobe, brand world, lighting family and color grade, but a new camera ' \
        'angle/framing or setting is expected here. It does not continue from a ' \
        'previous frame — establish this shot fully while staying visually consistent ' \
        'with the rest of the video.'

      CONTINUATION_DIRECTIVES = { self: SELF_CONTINUITY_DIRECTIVE, cut: CUT_DIRECTIVE }.freeze

      # Marks a prompt that already carries directives (scenes stored before
      # decoration moved to render time) — decorating those again would stack
      # boilerplate on every re-render.
      DECORATED_MARKER = 'On-screen text rule:'

      # camera: the isolated CINEMATOGRAPHY slot (one dominant move + shot/framing);
      #   blank ⇒ the serializer defaults it to a static locked-off shot.
      # model: the resolved engine slug — picks the prompt DIALECT (Seedance / Veo /
      #   Kling); blank ⇒ the configured default engine's dialect.
      # render_guardrails: hard prohibitions captured by the chat orchestrator
      #   ("what CANNOT happen") — merged with the client-positioning guardrails
      #   and enforced as negative constraints in the dialect's own phrasing.
      def initialize(prompt:, mode:, ctx:, continuation: false, with_audio: nil,
                     dialogue: nil, sound_effects: nil, on_screen_text: nil, voice_tone: nil,
                     voiced: false, guardrails: nil, references: [], identity: nil,
                     aspect_ratio: nil, target_seconds: nil, clip_seconds: nil,
                     camera: nil, model: nil, render_guardrails: nil)
        @prompt         = clean(prompt)
        @mode           = mode.to_s
        @ctx            = ctx
        @camera         = camera.to_s.strip.presence
        @model          = model.to_s.strip.presence
        @render_guardrails = render_guardrails
        @aspect         = aspect_ratio.to_s.presence || ctx.try(:aspect_ratio).to_s
        @continuation   = continuation
        @with_audio     = with_audio
        @dialogue       = dialogue.to_s.strip.presence
        # Diegetic sound the MODEL should generate for this scene (explosions,
        # footsteps…). Music is NEVER here — it's a separate post track.
        @sound_effects  = sound_effects.to_s.strip.presence
        @on_screen_text = on_screen_text.to_s.strip.presence
        @voice_tone     = voice_tone.to_s.strip.presence
        # True when a FIXED-voice audio track is attached as a reference — the
        # model must lip-sync to it, not invent its own voice.
        @voiced         = voiced == true
        @guardrails     = guardrails.to_s.strip.presence
        # Typed entries from Operations::Video::References ({ id:, url:, role:,
        # kind: }) in the SAME order the inputs are attached to the submission.
        @references     = Array(references)
        @identity       = identity.is_a?(Hash) ? identity : {}
        @target_seconds = target_seconds.to_f
        @clip_seconds   = clip_seconds.to_f
      end

      # Build the universal cinematic SPINE (PromptSpec) from this scene's data —
      # every existing input mapped to a slot, nothing dropped — then render it in
      # the engine's own DIALECT. The content of each slot is unchanged; only the
      # arrangement/phrasing is now engine-aware.
      def call
        PromptDialects.serialize(build_spec)
      end

      private

      def build_spec
        PromptSpec.new(
          cinematography: @camera,               # slot 1 (default filled by the serializer)
          narrative: @prompt,                    # slots 2–5: the storyboard's ordered visual prose
          style_fence: style_line,               # slot 5 augmentation: brand/production styling
          audio: audio_lines,                    # slot 6
          technical: [hold_line].compact,        # slot 7: pacing/trim
          identity: identity_line,               # cross-cutting contracts …
          continuity: continuity_line,
          references: References.manifest_lines(@references),
          on_screen_text: text_line,
          guardrails: guardrail_phrases,
          mode: i2v? ? :i2v : :t2v,
          dialect: dialect,
          aspect_ratio: @aspect
        )
      end

      # The engine dialect: from the resolved model slug, else the configured
      # default engine (so a bare call still serializes for the real engine).
      def dialect
        slug = @model.presence || VideoConfig.instance.model_for(@mode)
        PromptDialects.dialect_for_model(slug)
      end

      # Image-to-video: a seed frame conditions the render (a previous-frame
      # continuation or a keep-look re-render) → the prompt must describe motion
      # and change only, never re-describe the frame. A CUT or a fresh scene 1 is
      # text-to-video (no seed).
      def i2v? = %i[previous self].include?(@continuation)

      # The continuity contract as a ready line (nil for a seedless first scene).
      def continuity_line
        return nil unless @continuation

        "Continuity: #{CONTINUATION_DIRECTIVES.fetch(@continuation, CONTINUITY_DIRECTIVE)}"
      end

      # The negative constraints as raw phrases: the client-positioning guardrails
      # PLUS the chat-captured "cannot happen" prohibitions, split and de-duped.
      # The dialect decides how to phrase them (Seedance avoid-clause, Veo positive).
      def guardrail_phrases
        [@guardrails, *Array(@render_guardrails)]
          .compact
          .flat_map { |g| g.to_s.split(/[;\n]/) }
          .map(&:strip).reject(&:blank?).uniq
      end

      # Legacy scenes stored a fully-decorated prompt (directives baked in). We
      # recover just the clean visual description — the part before the first
      # appended contract — so re-compiling never stacks boilerplate NOR drops the
      # new first-class fields (the old pass-through silently discarded them).
      def clean(prompt)
        text = prompt.to_s
        cut = text.index(DECORATED_MARKER) || text.index("\nContinuity:") || text.index('. Continuity:')
        (cut ? text[0, cut] : text).strip
      end

      # The spoken-word contract. The exact PT-BR line is a first-class field so
      # the model can never "invent" speech: either these words, or none. When the
      # scene follows another, the background music/ambient must CONTINUE as one
      # soundtrack (models otherwise start a fresh track each clip — the "music
      # changes between scenes" problem).
      # The per-scene AUDIO CONTRACT — the orchestrator decides, per scene, what
      # the model must generate. Three independent knobs meet here:
      #   * DIALOGUE — dubbed (a fixed voice is laid in post → the model shows a
      #     silent talking performance) or native (no fixed voice → the model
      #     actually speaks the line).
      #   * SOUND EFFECTS — the diegetic sound the model should generate
      #     (explosions, footsteps…), or none.
      #   * MUSIC — NEVER the model's job; a single post track is burned in compose.
      # The boundary line then states EXACTLY what audio the model must and must
      # NOT produce, so a dubbed talking-head stays clean, an action scene gets its
      # SFX, and nothing ever competes with the post voice/music.
      def audio_lines
        return [] if @with_audio.nil? && @dialogue.nil? && @sound_effects.nil? # legacy: no contract
        return ['Audio: SILENT clip — generate NO audio of any kind (no speech, sound effects or music).'] if @with_audio == false

        parts = []
        speech =
          if @dialogue && @voiced
            parts << "The character says this line on camera: \"#{@dialogue}\". #{VOICE_POLICY}"
            :dubbed
          elsif @dialogue
            tone = @voice_tone ? " Delivered in a #{@voice_tone} tone." : ''
            parts << 'Dialogue — the character SPEAKS this line aloud, Brazilian Portuguese, EXACTLY ' \
                     "as written (nothing else is spoken): \"#{@dialogue}\".#{tone}"
            :native
          else
            :none
          end
        if @sound_effects
          parts << "Sound design — GENERATE the scene's diegetic sound: #{@sound_effects}. " \
                   'Match it to the on-screen action and timing.'
        end
        parts << audio_boundary(speech)
        parts.compact
      end

      # A fixed voice is DUBBED over the clip in post (OpenRouter's engines take no
      # driving-audio input → no in-model lip-sync). The model SHOWS the character
      # speaking but generates no voice audio. Asking it to "lip-sync to a provided
      # audio" (which it never gets) produced odd mouth behavior; this frames it as
      # a silent talking performance the fixed voice is laid over.
      VOICE_POLICY =
        'Show the character actually SPEAKING this line on camera — natural, well-timed ' \
        'lip and mouth movement, expression and gestures that fit the words and their pacing — ' \
        'but do NOT generate any spoken voice audio, voice-over or narration for it (the voice ' \
        'is a fixed track dubbed in afterward).'

      # States the exact audio the model MUST and MUST NOT produce, from the scene's
      # speech mode + whether it has SFX. Music is ALWAYS excluded (a post track);
      # a dubbed voice is excluded (added in post); SFX are the only model audio
      # kept when there's no native speech.
      NO_MUSIC = 'NEVER generate any music, soundtrack, score, song, jingle or background music ' \
                 '(a single track is added separately in post — model music would clash with it).'

      def audio_boundary(speech)
        case speech
        when :dubbed
          if @sound_effects
            "Audio boundary: the diegetic sound effects above are the ONLY audio to generate — do " \
              "NOT generate any spoken voice or dialogue audio (the voice is dubbed in post). #{NO_MUSIC}"
          else
            'Audio boundary: render this clip SILENT — generate NO audio at all (no voice, no ambient, ' \
              'no effects); the voice and music are added in post.'
          end
        when :native
          extra = @sound_effects ? 'the spoken line and the diegetic sound effects above' : "the spoken line and the scene's incidental natural sound"
          "Audio boundary: #{extra} are the ONLY audio — no other voices. #{NO_MUSIC}"
        else # :none
          if @sound_effects
            "Audio boundary: the diegetic sound effects above are the ONLY audio — no voices or dialogue. #{NO_MUSIC}"
          else
            'Audio boundary: render this clip SILENT — generate NO audio; voice and music are added in post.'
          end
        end
      end

      # The LOCKED project identity — the character/wardrobe/setting/palette/style
      # that must stay IDENTICAL across every scene of the video. This is the
      # director's continuity constraint: models otherwise drift (a new face, a
      # different outfit) between clips. Reapplied to every scene, not just
      # continuations.
      def identity_line
        bits = []
        if @identity['has_character'] && @identity['character'].present?
          bits << "the SAME character throughout (identical face and appearance): #{@identity['character']}"
        elsif @identity['has_character'] == false
          bits << 'no recurring character/person — this video has no on-camera protagonist'
        end
        bits << "wardrobe/styling: #{@identity['wardrobe']}" if @identity['wardrobe'].present?
        bits << "setting/world: #{@identity['scenario']}" if @identity['scenario'].present?
        bits << "color palette: #{@identity['palette']}" if @identity['palette'].present?
        bits << "visual style: #{@identity['style']}" if @identity['style'].present?
        return nil if bits.empty?

        "Project identity — keep IDENTICAL in every scene (never drift between " \
          "scenes): #{bits.join('; ')}."
      end

      # The engine renders FIXED-length clips (4/6/8s), but the shown scene is
      # TRIMMED to its audio-driven target length. When the rendered clip is
      # longer than that target, tell the model to finish the meaningful action by
      # the target second and HOLD after it (no new action/subject/cut) — so the
      # trim point is a clean, settled frame and the pacing follows the audio, not
      # the model's fixed clip size. Only emitted when a real trim will happen.
      HOLD_MARGIN = 0.75
      def hold_line
        return nil unless @target_seconds.positive? && @clip_seconds > @target_seconds + HOLD_MARGIN

        secs = @target_seconds.round
        "Pacing/trim: this clip is #{@clip_seconds.round}s but the scene is TRIMMED to about " \
          "#{secs}s — fit ALL the meaningful action (and the full spoken line) within the FIRST " \
          "#{secs} seconds. After second #{secs}, HOLD the final composition steady: no new action, " \
          'no new subject entering, no cut, no fade — just a settled frame. Everything after that ' \
          'point is discarded, so nothing important may happen there.'
      end

      # Hard brand "avoid" constraints — the render model invents props, wardrobe
      # and set beyond the visual prompt, so these must reach it as a do-not list
      # (a compliant storyboard alone can't stop the model from adding a forbidden
      # element at render time).
      def avoid_line
        return nil if @guardrails.blank?

        "Hard brand constraints — the scene must NOT contain any of: #{@guardrails}."
      end

      # Per-format typography: placement + safe area so the text is legible and
      # not cropped/clipped by the platform UI in each aspect ratio.
      FONT_GUIDANCE = {
        '9:16' => 'large, bold, high-contrast sans-serif; centered in the LOWER THIRD, well inside ' \
                  'safe margins — keep clear of the top ~10% and bottom ~15% (the platform UI zones)',
        '4:5'  => 'bold, high-contrast sans-serif; centered, generous safe margins',
        '1:1'  => 'bold, high-contrast sans-serif; centered, generous safe margins',
        '16:9' => 'clean, bold sans-serif as a lower-third; inside title-safe margins (~5% from every edge)'
      }.freeze

      # Lettering contract: the exact text, styled/placed for the format, or none
      # at all — garbled/invented or cropped typography ruins an otherwise good scene.
      def text_line
        return 'On-screen text: NONE — never invent lettering, captions, subtitles, logos or watermarks.' unless @on_screen_text

        font = FONT_GUIDANCE[@aspect] || FONT_GUIDANCE['9:16']
        'On-screen text (must appear EXACTLY as written, correctly spelled and fully legible): ' \
          "\"#{@on_screen_text}\". Typography: #{font}. Render it crisp and unobstructed; " \
          'no other lettering, captions or watermarks anywhere.'
      end

      # The reference MANIFEST: each attached input anchored by position (the
      # API carries no names), named by its stable identifier (img_character_v1,
      # vid_camera_ref_v1, …) and bound to its role's ONE-job contract — an
      # unlabeled pile of inputs reads as "put all of this in the video". The
      # scene prompt cites the identifiers; the manifest is what resolves them.
      def references_line
        return nil if @references.empty?

        lines = References.manifest_lines(@references)
        "Reference manifest — the attached inputs in order; each has exactly ONE job, " \
          "never blend jobs across references:\n" \
          "#{lines.map { |l| "- #{l}" }.join("\n")}\n" \
          'When this prompt cites an identifier above, follow that reference exactly for ' \
          'its job and nothing else.'
      end

      # Look-and-feel GUIDANCE — never machine-metadata. Brand colors are given
      # as NAMES to grade toward (never hex codes, which the model stamps on the
      # frame), the tone/direction as plain look guidance, all under an explicit
      # "do not display any of this as text" rule. The brand NAME is intentionally
      # omitted here (the scene's visual prompt places the wordmark when it should
      # appear; a bare "brand: X" label just leaks onto the frame).
      def style_line
        bits = []
        bits << "keep the mood #{@ctx.brand_voice}" if brand_voice_meaningful?
        colors = palette_names
        bits << "grade toward the brand colors (#{colors})" if colors.present?
        bits << "follow this direction: #{@ctx.production_scope}" if @ctx.production_scope.present?
        return nil if bits.empty?

        'Look & feel (guidance to shape styling, casting, lighting and color grade only — ' \
          'apply the colors as lighting, wardrobe, set and accents; NEVER show any color ' \
          "name, hex code, label or these words as on-screen text): #{bits.join('; ')}."
      end

      # Brand colors as natural names ("deep green and warm amber"), so the model
      # grades toward them instead of printing "#035e09".
      def palette_names
        [@ctx.brand_primary, @ctx.brand_secondary]
          .map { |hex| ColorName.call(hex) }
          .compact.uniq.join(' and ')
      end

      # The generic default voice carries no real direction — skip it rather than
      # inject boilerplate a literal model might read as content.
      DEFAULT_VOICE = 'tom profissional, próximo e criativo'

      def brand_voice_meaningful?
        @ctx.brand_voice.present? && @ctx.brand_voice != DEFAULT_VOICE
      end
    end
  end
end
