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
  # Context keys: mode ('avatar' | 'product'), brief, script, total_duration,
  # aspect_ratio, max_scenes (int), has_references (bool), has_logo (bool),
  # has_avatar (bool).
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
        - duration_seconds (optional, #{MIN_SCENE_SECONDS}–#{SCENE_UNIT_SECONDS}s
          per scene): pace the edit — short beats for quick cuts, longer for a
          held moment. Omit to use an even split.
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
        'Sound is ON: put each scene\'s EXACT spoken line(s) in its dialogue ' \
          'field (Brazilian Portuguese, final wording — it is spoken verbatim). ' \
          'A scene with an empty dialogue field renders with ambient sound only. ' \
          'Never write spoken words inside the visual prompt. Scenes carry NO ' \
          'background music — a single royalty-free track is searched from an open ' \
          'base and burned in post. In `music`, write the search `query` (English ' \
          'mood + genre) and the mix (`volume`, `fade_in`, `fade_out`, `duck`) that ' \
          'fit the video; omit `music` entirely for no music.'
      end
    end

    # The duration → scene-count contract, stated as an unmissable rule.
    def scene_budget_rule
      max = context[:max_scenes].to_i.clamp(1, 12)
      base = "The video is ~#{context[:total_duration]}s TOTAL at #{context[:aspect_ratio]}; " \
             'each scene renders as ONE continuous shot of about 8 seconds.'
      if max == 1
        "#{base} This video fits a SINGLE scene — return EXACTLY ONE scene."
      else
        "#{base} HARD LIMIT: at most #{max} scenes."
      end
    end

    # What visual-identity assets ride along to the RENDERER as reference images,
    # so the storyboard can write scenes knowing they exist.
    def identity_assets_block
      bits = []
      if context[:has_logo]
        bits << '- the brand LOGO (context only — the video does not need to show any logo; ' \
                'if branding naturally appears, it must be exactly this one)'
      end
      bits << '- the creator AVATAR (the on-camera person must faithfully match this face)' if context[:has_avatar]
      return '' if bits.empty?

      "Visual references the renderer receives with every scene:\n#{bits.join("\n")}"
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
      parts << 'Product reference photos are attached — keep the product faithful.' if context[:has_references]
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
                  'duration_seconds' => { 'type' => 'integer', 'description' => "Optional pacing for this shot, #{MIN_SCENE_SECONDS}–#{SCENE_UNIT_SECONDS}s. Omit for an even split." },
                  'continues_previous' => { 'type' => 'boolean', 'description' => 'true (default) = continues the previous shot seamlessly from its final frame; false = a CUT (new shot/scenario, same characters and world, does NOT start from the previous frame). Ignored for the first scene.' }
                }
              }
            }
          }
        }
      }
    end

    private

    def mode_guidance
      if context[:mode].to_s == 'product'
        'PRODUCT mode: the product is the hero. Show it in angles and motion that sell, ' \
          'always faithful to the reference photos (shape, colors, label).'
      else
        'AVATAR mode: a person talking to camera (authentic UGC, selfie framing, natural light). ' \
          'Distribute the script naturally across the scenes.'
      end
    end
  end
end
