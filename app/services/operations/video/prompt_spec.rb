# frozen_string_literal: true

module Operations
  module Video
    # The universal CINEMATIC SPINE for one scene's render prompt — dialect-agnostic.
    # DecoratePrompt fills a PromptSpec from the scene's data (mapping every existing
    # input into a slot; nothing is dropped); a PromptDialects serializer then renders
    # it into the exact shape a specific engine wants (Seedance / Veo / Kling / …).
    #
    # The seven slots, in canonical order:
    #   1. cinematography — camera movement + shot type + framing (ALWAYS present;
    #      the serializer defaults it to a static locked-off shot when blank). Held
    #      apart from subject motion so the two never tangle in one clause.
    #   2..5 subject / action / setting / style — the visual narrative. We keep
    #      these as ONE `narrative` string (the storyboard writes it in that order);
    #      `style_fence` carries the brand/production styling that augments slot 5.
    #   6. audio — the per-scene audio contract lines (dialogue / SFX / boundary).
    #   7. technical — trim/hold pacing, lettering safe-area, quality hints.
    #
    # Cross-cutting contracts that every dialect must still emit (never lost):
    #   identity, continuity, references (typed manifest), on_screen_text, guardrails.
    #
    # Metadata drives serialization: `dialect` (which engine), `mode` (:t2v | :i2v),
    # aspect ratio, and whether a reference/seed frame is present.
    PromptSpec = Struct.new(
      # slot 1
      :cinematography,
      # slots 2–5 (the storyboard's ordered visual narrative) + brand styling
      :narrative,
      :style_fence,
      # slot 6 — array of audio-contract lines
      :audio,
      # slot 7 — array of technical/pacing lines
      :technical,
      # cross-cutting contracts
      :identity,
      :continuity,
      :references,       # array of manifest lines ("input 1 = img_x: …")
      :on_screen_text,   # lettering directive (string) or nil
      :guardrails,       # array of raw "avoid" phrases (dialect phrases them)
      # metadata
      :mode,             # :t2v | :i2v
      :dialect,          # :seedance | :veo | :kling | :default
      :aspect_ratio,
      keyword_init: true
    ) do
      def i2v? = mode == :i2v

      def audio_lines = Array(audio).compact
      def technical_lines = Array(technical).compact
      def reference_lines = Array(references).compact
      def guardrail_phrases = Array(guardrails).map { |g| g.to_s.strip }.reject(&:blank?)

      # Cinematography is never left unspecified — a blank camera reads to the model
      # as "do whatever", which yields drifting, uncontrolled motion.
      DEFAULT_CAMERA = 'static locked-off shot'
      def camera = cinematography.to_s.strip.presence || DEFAULT_CAMERA
    end
  end
end
