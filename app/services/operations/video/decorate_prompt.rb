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

      def initialize(prompt:, mode:, ctx:, continuation: false, with_audio: nil,
                     dialogue: nil, on_screen_text: nil, voice_tone: nil, voiced: false,
                     guardrails: nil, references: [], identity: nil, aspect_ratio: nil)
        @prompt         = clean(prompt)
        @mode           = mode.to_s
        @ctx            = ctx
        @aspect         = aspect_ratio.to_s.presence || ctx.try(:aspect_ratio).to_s
        @continuation   = continuation
        @with_audio     = with_audio
        @dialogue       = dialogue.to_s.strip.presence
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
      end

      def call
        lines = [@prompt, '']
        lines << identity_line
        lines << "Continuity: #{CONTINUATION_DIRECTIVES.fetch(@continuation, CONTINUITY_DIRECTIVE)}" if @continuation
        lines.concat(audio_lines)
        lines << text_line
        lines << references_line
        lines << avoid_line
        lines << style_line
        lines.compact.join("\n").strip
      end

      private

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
      def audio_lines
        return [] if @with_audio.nil? && @dialogue.nil? # legacy generations: no contract to state
        return ['Audio: SILENT video — no speech, no voice-over, no on-camera talking.'] if @with_audio == false

        lines =
          if @dialogue && @voiced
            # A fixed-voice audio track is provided as a reference — lip-sync to it.
            ["Dialogue (Brazilian Portuguese; NOTHING else may be spoken in this scene): " \
             "\"#{@dialogue}\". #{VOICE_POLICY}"]
          elsif @dialogue
            tone = @voice_tone ? " Delivered in a #{@voice_tone} tone." : ''
            ['Dialogue (Brazilian Portuguese — spoken EXACTLY as written; NOTHING else may be ' \
             "spoken in this scene): \"#{@dialogue}\".#{tone}"]
          else
            ['Audio: no dialogue in this scene — ambient/natural sound only, no voice-over.']
          end
        lines << MUSIC_POLICY
        lines.compact
      end

      # A single FIXED voice is used for the WHOLE video: the exact spoken audio is
      # provided as an audio reference. The character must lip-sync to THAT audio
      # and reproduce that exact voice — never invent a different voice/timbre —
      # so the voice is identical across every scene.
      VOICE_POLICY =
        'The spoken line is provided as an AUDIO REFERENCE (a fixed voice). The on-camera ' \
        'speaker must lip-sync to that exact audio and keep that exact voice and timbre — ' \
        'do NOT generate a different voice, accent or delivery.'

      # The video model NEVER generates music: the platform picks ONE royalty-free
      # track and burns it under the whole video at compose. So each clip must have
      # NO music — only the spoken dialogue and natural/ambient/diegetic sound. This
      # is what keeps the soundtrack continuous (one track, added in post) instead
      # of a different AI-generated track per clip.
      # Best-practice for the current engines (Veo/Seedance): POSITIVELY name the
      # only audio wanted (dialogue + natural diegetic sound) AND state the
      # exclusion as an explicit negative — these models honor negatives like
      # "(no music)". The soundtrack is a single track added in post; any music
      # generated in the clip would double up with it.
      MUSIC_POLICY =
        'Audio contains ONLY the spoken dialogue and the natural, diegetic sound that physically ' \
        'belongs to this scene (room tone, footsteps, ambient noise, the sounds of the objects/place ' \
        'shown). Absolutely NO music of any kind — no soundtrack, score, song, jingle, hum or ' \
        'background music. (no music, no background music, no musical score, no soundtrack.) ' \
        'The music is added separately in post-production; any music here would clash with it.'

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
