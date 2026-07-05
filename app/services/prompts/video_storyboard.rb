# frozen_string_literal: true

module Prompts
  # Breaks a video brief into a STORYBOARD — the right number of scenes, each a
  # coherent continuous beat, never filler. The requested duration is a HARD
  # scene budget (each scene renders as one ~8s model clip): the model decides
  # how many scenes the idea actually needs UP TO that budget — an 8s video is
  # exactly one scene. Each scene continues visually from the previous one (the
  # pipeline seeds the next scene with the previous scene's last frame), so
  # prompts should read as one flowing shot list, not disconnected clips.
  #
  # System/tool text is ENGLISH (code); only the user-facing outputs (scene
  # captions) are produced in PT-BR, per the language rules.
  #
  # Context keys: mode (VideoConfig::MODES), brief, script, total_duration,
  # aspect_ratio, max_scenes (int), has_references (bool), media_references
  # (typed entries from Operations::Video::References — identifier + role).
  class VideoStoryboard < Base
    STORYBOARD_TOOL = 'storyboard'
    MIN_SCENE_SECONDS = 4  # mirrors Operations::Video::PlanScenes
    SCENE_UNIT_SECONDS = 8

    def system
      <<~TXT.strip
        You are a short-form social video director. You receive a brief and must
        turn it into a STORYBOARD: a sequence of scenes that together form ONE
        cohesive, engaging video.

        #{brand_block}

        #{positioning_block}

        #{identity_assets_block}

        Rules:
        - LOCK THE PROJECT IDENTITY FIRST (fill `identity`). You are the director:
          decide the SCOPE — does the video have a recurring on-camera CHARACTER
          (a person/mascot/spokesperson, has_character = true) or not (product,
          scenery, abstract, has_character = false)? Then fix the consistent
          identity every scene must share: character (same face/appearance, only
          if has_character), wardrobe, setting/world, color palette and visual
          style. These are LOCKED — every scene reuses them so the video reads as
          one piece; do not drift between scenes. WRITE the identity descriptions
          (character, wardrobe, setting, palette, style) in BRAZILIAN PORTUGUESE —
          they are shown to the user in the editor.
        - CONSISTENCY ANCHORS (optional, you decide): when a recurring CHARACTER or
          a distinctive SCENARIO must stay identical across scenes AND the user gave
          NO photo of it, request a generated reference image in `generated_references`
          — each entry { role: "character" | "scene", prompt: "<a detailed depiction
          of ONE subject on a neutral background>" }. Generated ONCE and fed to EVERY
          scene, locking the look. If the video features MORE THAN ONE recurring
          person/character (e.g. two people talking, a duo, a host + guest, several
          avatars), request ONE character entry PER person — each with its own prompt
          — so every one gets its own locked reference, never a single shared one.
          Each costs an image credit, so request them ONLY when they materially help
          consistency (recurring characters/presenters, or a signature set), one per
          DISTINCT subject; skip generic/one-off visuals or when a good photo exists.
        - #{scene_budget_rule}
        - GET THE MESSAGE RIGHT, grounded ONLY in the brief and positioning above
          (never in outside assumptions). Say truthfully what the brand DOES for
          its audience. Do not conflate the brand with its users: a character who
          represents the audience speaks as a USER who benefits from the brand,
          never voicing a claim that only makes sense from the company's own
          mouth. When unsure, promote the concrete BENEFIT the audience gets, in
          their own words.
        - Create ONLY the scenes the idea actually needs within that budget.
          Never invent scenes to fill time — every scene must have a clear
          purpose. Using fewer scenes than the budget is fine; exceeding it is not.
        - Scenes are SEQUENTIAL BEATS of one video. By DEFAULT each later scene
          CONTINUES the previous shot seamlessly (continues_previous = true):
          it picks up from the previous scene's final frame — same location,
          framing and moment moving forward. Write these as "what happens NEXT",
          never as a retake of the same concept.
        - A scene may instead be a CUT (continues_previous = false): a NEW shot
          in the SAME video — same characters/subject and brand world, but a
          different framing, angle or scenario (e.g. cut from the person talking
          to a wide shot of the team, or to the product on a desk). Use a cut
          when the story needs a new vantage/scenario, NOT to restate the same
          beat. A cut does NOT start from the previous frame, so describe its
          setting fully (while keeping the same characters, wardrobe and grade).
        - Keep ONE cohesive world across the whole video: same subjects, brand
          look, lighting family and color grade — cuts included. It must read as
          one piece, not random clips.
        - #{duration_rule}
        - The brand block and positioning above are BACKGROUND CONTEXT: they
          guide tone, styling, casting and message. Never paste them into a
          scene as spoken lines, captions or on-screen text.
        - Each scene prompt is a rich, specific ENGLISH visual description for
          the video model (camera, action, setting, lighting, pacing) — PURELY
          VISUAL: no spoken lines, no lettering instructions inside it. Faithful
          to the brand and the brief; never distort the product or invent
          foreign elements.
        - #{audio_rule}
        - on_screen_text: the EXACT final text for the scene (Brazilian
          Portuguese, correctly spelled) — or leave it empty for a text-free
          scene. Most scenes should have NO text; use it only when lettering
          genuinely serves the message.
        - #{mode_guidance}
        - Each scene caption is a short BRAZILIAN PORTUGUESE summary of that scene
          for the human editor (it is not on-screen text).

        Return the storyboard by calling the tool.
      TXT
    end

    # Speech is field-controlled: the exact line in `dialogue`, or silence —
    # otherwise the video model invents dialogue.
    def audio_rule
      if context[:with_audio] == false
        'This video is SILENT: leave every dialogue field EMPTY — no scene may ' \
          'contain speech or a voice-over.'
      else
        ['Sound is ON: put each scene\'s EXACT spoken line(s) in its dialogue ' \
         'field (Brazilian Portuguese, final wording — it is spoken verbatim). ' \
         'A scene with an empty dialogue field renders with ambient sound only. ' \
         'Never write spoken words inside the visual prompt. Scenes carry NO ' \
         'background music — a single royalty-free track is searched from an open ' \
         'base and burned in post. In `music`, write the search `query` (English ' \
         'mood + genre) and the mix (`volume`, `fade_in`, `fade_out`, `duck`) that ' \
         'fit the video; omit `music` entirely for no music.', voice_rule].compact.join(' ')
      end
    end

    # ONE fixed voice for the WHOLE video (a real TTS speaker synthesized per
    # scene) so the voice never drifts between clips. Offered from the live voice
    # library; picked to MATCH the character (gender/persona/energy). Empty ⇒ the
    # model's native audio is used as-is.
    def voice_rule
      opts = Array(context[:voices]).first(14).filter_map do |v|
        name = v.is_a?(Hash) ? v[:name].to_s.strip : v.to_s.strip
        next if name.blank?

        desc = v.is_a?(Hash) ? [v[:gender], v[:country], v[:description]].map(&:to_s).reject(&:blank?).join(', ') : ''
        desc.present? ? "#{name} (#{desc})" : name
      end
      return nil if opts.empty?

      'The spoken voice is ONE fixed voice for the whole video (same speaker in ' \
        'every scene). In `voice`, pick exactly ONE NAME that best fits the ' \
        "CHARACTER (gender/persona/energy) from: #{opts.join('; ')}. Omit `voice` to use the default."
    end

    # The engine renders FIXED-length clips: each scene's duration must be ONE of
    # the supported lengths, never an arbitrary number. State the options.
    def clip_seconds
      opts = Array(context[:clip_seconds]).map(&:to_i).reject(&:zero?).uniq.sort
      opts.presence || [SCENE_UNIT_SECONDS]
    end

    def duration_rule
      opts = clip_seconds
      "duration_seconds: the engine renders FIXED-length clips, so EACH scene's duration MUST be " \
        "exactly one of these supported lengths: #{opts.join(', ')}s. YOU estimate each scene's " \
        'length — scenes can (and should) have DIFFERENT lengths, chosen to fit their beat (shorter ' \
        'for a quick cut, longer for a held moment). The sum of all durations must be about the total.'
    end

    # The duration → scene-count contract, stated as an unmissable rule.
    def scene_budget_rule
      total = context[:total_duration].to_i
      max = context[:max_scenes].to_i.clamp(1, 12)
      base = "The video is ~#{total}s TOTAL at #{context[:aspect_ratio]}. The SUM of your scenes' " \
             "duration_seconds must add up to ~#{total}s and NEVER exceed it — each scene is one " \
             'rendered clip.'
      if max == 1
        "#{base} At this length it is a SINGLE clip — return EXACTLY ONE scene. If you want an " \
          'internal cut/beat change, describe it INSIDE that one scene\'s prompt (a mid-shot cut), ' \
          'do NOT add a second scene.'
      else
        "#{base} Use the FEWEST scenes that tell it well, at most #{max}. Give each scene the length " \
          "that fits its beat so the durations add up to ~#{total}s (e.g. #{budget_example(total)})."
      end
    end

    # A concrete "durations that sum to the total" example, from the supported
    # lengths — so the model sees the shape it must match.
    def budget_example(total)
      opts = clip_seconds
      combo = []
      remaining = total
      while remaining >= opts.min && combo.size < 6
        pick = opts.select { |o| o <= remaining }.max || opts.min
        combo << pick
        remaining -= pick
      end
      combo = [opts.min] if combo.empty?
      "#{combo.join('s + ')}s = #{combo.sum}s"
    end

    # The TYPED media references the renderer receives with every scene — each
    # with its stable identifier (img_product_v1, vid_camera_ref_v1, …) and its
    # ONE job. The storyboard writes scenes knowing exactly what exists, and
    # cites the identifiers in scene prompts (Operations::Video::References is
    # the single source of these contracts).
    def identity_assets_block
      entries = Array(context[:media_references])
      return '' if entries.empty?

      lines = Operations::Video::References.manifest_lines(entries)
      "Media references the renderer receives with every scene — each has ONE job:\n" \
        "#{lines.map { |l| "- #{l}" }.join("\n")}\n" \
        'When a scene should draw on a reference, cite it by its identifier in the scene ' \
        "prompt (e.g. \"#{citation_example(entries.first)}\") — the renderer maps " \
        'identifiers to the attached inputs. Never invent identifiers that are not listed.'
    end

    # Everything the storyboard is built from — the full planning direction, so
    # the scenes carry the ticket's actual content, message and constraints, not
    # just the brand. (Empty parts drop out.)
    def brief_context
      parts = []
      parts << "Brief: #{context[:brief]}" if context[:brief].present?
      parts << "Script/speech (use as the spoken lines): #{context[:script]}" if context[:script].present?
      parts << "Goal of the video: #{context[:objective]}" if context[:objective].present?
      parts << "Target audience: #{context[:persona]}" if context[:persona].present?
      parts << "Content pillar: #{context[:content_pillar]}" if context[:content_pillar].present?
      parts << "Production direction (what to show / avoid / must include): #{context[:production_scope]}" if context[:production_scope].present?
      parts << "Reference material: #{context[:references]}" if context[:references].present?
      if context[:positioning_brief].present?
        parts << "Client positioning (shapes the message and tone — do NOT recite verbatim):\n#{context[:positioning_brief]}"
      end
      # Attachments are described precisely by the typed manifest (identity_assets_block,
      # each with its role + contract) — no generic "product photos" line here, which
      # would contradict a style/camera/motion reference's "never copy its subject".
      parts.join("\n")
    end

    def self.storyboard_tool
      {
        'name' => STORYBOARD_TOOL,
        'description' => 'Returns the video storyboard: the ordered list of needed scenes, each ' \
                         'with a visual prompt (English) and a caption (Brazilian Portuguese), ' \
                         'plus optional per-scene pacing (duration) and whether it continues the ' \
                         'previous shot or is a cut.',
        'input_schema' => {
          'type' => 'object', 'required' => %w[scenes],
          'properties' => {
            'mode' => {
              'type' => 'string', 'enum' => VideoConfig::MODES,
              'description' => 'The video KIND — keep the user\'s pick or switch to a better fit ' \
                               '(you may use modes the UI doesn\'t offer). Respect the assets the user gave.'
            },
            'identity' => {
              'type' => 'object',
              'description' => 'The LOCKED project identity — the consistent look every scene shares ' \
                               '(the director\'s decision). Descriptions in BRAZILIAN PORTUGUESE (they ' \
                               'are shown to the user in the editor).',
              'properties' => {
                'has_character' => { 'type' => 'boolean', 'description' => 'true = a recurring on-camera person/mascot/spokesperson; false = product/scenery/abstract (no character).' },
                'character' => { 'type' => 'string', 'description' => 'The character (same face/appearance in every scene) — only when has_character.' },
                'wardrobe' => { 'type' => 'string', 'description' => 'Consistent clothing/styling.' },
                'scenario' => { 'type' => 'string', 'description' => 'The consistent setting/world.' },
                'palette' => { 'type' => 'string', 'description' => 'Color identity (words, not hex).' },
                'style' => { 'type' => 'string', 'description' => 'Overall visual style/grade (e.g. "warm golden-hour realistic UGC").' }
              }
            },
            'voice' => {
              'type' => 'string',
              'description' => 'The ONE fixed voice for the whole video — pick a label from the ' \
                               'voice options in the rules (same speaker in every scene). Omit for the default.'
            },
            'generated_references' => {
              'type' => 'array',
              'description' => 'OPTIONAL: reference images to GENERATE (via an image model) to lock ' \
                               'recurring characters/scenario across scenes when the user gave no photo. ' \
                               'Request ONE "character" entry PER recurring person/character (several people ' \
                               '=> several entries), plus optionally one "scene". Each is generated once and ' \
                               'used as a reference in every scene. Costs an image credit each — only when it ' \
                               'materially helps consistency. Max 4.',
              'items' => {
                'type' => 'object', 'required' => %w[role prompt],
                'properties' => {
                  'role' => { 'type' => 'string', 'enum' => %w[character scene], 'description' => 'character = the recurring subject; scene = the signature setting.' },
                  'prompt' => { 'type' => 'string', 'description' => 'A detailed depiction of the subject on a neutral background (English), matching the locked identity.' }
                }
              }
            },
            'music' => {
              'type' => 'object',
              'description' => 'The single royalty-free background track added in post (scenes carry ' \
                               'no music). YOU control the search AND the mix. Omit entirely for no music.',
              'properties' => {
                'query' => { 'type' => 'string', 'description' => 'Search terms for the open music base, in English — mood + genre + energy + instrumentation (e.g. "upbeat corporate motivational instrumental", "calm ambient piano").' },
                'mood' => { 'type' => 'string', 'enum' => VideoConfig::MUSIC_MOODS, 'description' => 'One-word mood (also shown to the user).' },
                'volume' => { 'type' => 'number', 'description' => 'Music level under the audio, 0.05–0.6. Lower it (≈0.2) when scenes have dialogue, higher (≈0.4) for a music-forward video.' },
                'fade_in' => { 'type' => 'number', 'description' => 'Fade-in seconds at the start, 0–3.' },
                'fade_out' => { 'type' => 'number', 'description' => 'Fade-out seconds at the end, 0–5.' },
                'duck' => { 'type' => 'boolean', 'description' => 'true = automatically lower the music under the spoken dialogue (recommended whenever there is speech).' }
              }
            },
            'scenes' => {
              'type' => 'array',
              'description' => 'The scenes in order. Only what is needed, within the scene budget — no filler scenes.',
              'items' => {
                'type' => 'object', 'required' => %w[prompt caption],
                'properties' => {
                  'prompt' => { 'type' => 'string', 'description' => 'PURELY VISUAL description of the scene, in English (camera, action, setting, lighting). No spoken lines, no lettering instructions.' },
                  'dialogue' => { 'type' => 'string', 'description' => 'EXACT spoken line(s) of the scene, Brazilian Portuguese, final wording — spoken verbatim. Empty/omitted = no speech in the scene.' },
                  'on_screen_text' => { 'type' => 'string', 'description' => 'EXACT on-screen text, Brazilian Portuguese, correctly spelled. Empty/omitted = a text-free scene (the default).' },
                  'caption' => { 'type' => 'string', 'description' => 'Short scene summary in Brazilian Portuguese (for the editor).' },
                  'duration_seconds' => { 'type' => 'integer', 'description' => 'Optional pacing for this shot — MUST be one of the engine\'s supported clip lengths listed in the rules (fixed-length clips). Omit for an even split.' },
                  'continues_previous' => { 'type' => 'boolean', 'description' => 'true (default) = continues the previous shot seamlessly from its final frame; false = a CUT (new shot/scenario, same characters and world, does NOT start from the previous frame). Ignored for the first scene.' }
                }
              }
            }
          }
        }
      }
    end

    private

    # A citation example matched to the FIRST reference's actual role, so the
    # hint never says "the product from img_avatar_v1". Falls back to a neutral
    # phrasing for roles without a natural noun.
    CITATION_PHRASES = {
      'character' => 'the character from', 'avatar' => 'the person from',
      'product' => 'the product from', 'scene' => 'the setting from',
      'style' => 'match the style of', 'camera' => 'use the camera move of',
      'motion' => 'match the motion of', 'logo' => 'the brand mark from'
    }.freeze

    def citation_example(entry)
      phrase = CITATION_PHRASES.fetch(entry[:role], 'draw on')
      "#{phrase} #{entry[:id]}"
    end

    # The video MODE. The user picked one, but YOU (the director) may keep it or
    # switch to a better fit — including modes the UI never offers. Respect what
    # the user actually gave: if there are product photos, stay PRODUCT; if they
    # asked for a person talking, stay AVATAR.
    def mode_guidance
      current = context[:mode].to_s
      lines = VideoConfig::MODES.map do |m|
        mark = m == current ? ' (the user picked this)' : ''
        "#{m} — #{VideoConfig::MODE_GUIDANCE[m]}#{mark}"
      end
      "MODE: set `mode` to the best fit for the content (default: keep the user's). Options:\n" \
        "#{lines.join("\n")}"
    end
  end
end
