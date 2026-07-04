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
        'the concept; no cut, no scene reset, no new location.'

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
                     dialogue: nil, on_screen_text: nil, voice_tone: nil,
                     guardrails: nil, reference_labels: [])
        @prompt           = clean(prompt)
        @mode             = mode.to_s
        @ctx              = ctx
        @continuation     = continuation
        @with_audio       = with_audio
        @dialogue         = dialogue.to_s.strip.presence
        @on_screen_text   = on_screen_text.to_s.strip.presence
        @voice_tone       = voice_tone.to_s.strip.presence
        @guardrails       = guardrails.to_s.strip.presence
        @reference_labels = Array(reference_labels)
      end

      def call
        lines = [@prompt, '']
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
          if @dialogue
            tone = @voice_tone ? " Delivered in a #{@voice_tone} tone." : ''
            ['Dialogue (Brazilian Portuguese — spoken EXACTLY as written; NOTHING else may be ' \
             "spoken in this scene): \"#{@dialogue}\".#{tone}"]
          else
            ['Audio: no dialogue in this scene — ambient/natural sound only, no voice-over.']
          end
        lines << MUSIC_POLICY
        lines.compact
      end

      # The video model NEVER generates music: the platform picks ONE royalty-free
      # track and burns it under the whole video at compose. So each clip must have
      # NO music — only the spoken dialogue and natural/ambient/diegetic sound. This
      # is what keeps the soundtrack continuous (one track, added in post) instead
      # of a different AI-generated track per clip.
      MUSIC_POLICY =
        'Background music: add NONE — no soundtrack, score or background song of any kind. ' \
        'Only the spoken dialogue and natural/ambient/diegetic sound. The music is added ' \
        'later in post-production, so any music in the clip would clash — keep it music-free.'

      # Hard brand "avoid" constraints — the render model invents props, wardrobe
      # and set beyond the visual prompt, so these must reach it as a do-not list
      # (a compliant storyboard alone can't stop the model from adding a forbidden
      # element at render time).
      def avoid_line
        return nil if @guardrails.blank?

        "Hard brand constraints — the scene must NOT contain any of: #{@guardrails}."
      end

      # Lettering contract: the exact text, or none at all — garbled/invented
      # typography ruins an otherwise good scene.
      def text_line
        if @on_screen_text
          'On-screen text (must appear EXACTLY as written, correctly spelled and legible): ' \
            "\"#{@on_screen_text}\". No other lettering, captions or watermarks anywhere."
        else
          'On-screen text: NONE — never invent lettering, captions, subtitles, logos or watermarks.'
        end
      end

      # Positional manifest so the model knows what EACH attached reference is
      # for — an unlabeled pile of images reads as "put all of this in the video".
      def references_line
        return nil if @reference_labels.empty?

        "Reference images: #{@reference_labels.join('; ')}."
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
