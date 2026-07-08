# frozen_string_literal: true

module Operations
  module Video
    module PromptDialects
      # Shared serialization scaffolding. A dialect implements only #creative_block
      # (how it arranges the camera + visual narrative + style + audio — the part
      # that genuinely differs per engine) and, when its engine wants it, overrides
      # #guardrails_line (negatives are phrased differently: Seedance an in-prompt
      # "avoid" clause, Veo positive-only, Kling a separate field). Everything else
      # — the identity/continuity/reference-manifest/on-screen-text/technical
      # contracts — is dialect-agnostic natural language and stays IDENTICAL across
      # engines, so no rule or context source is ever lost when the dialect changes.
      class Base
        def self.call(spec) = new(spec).call

        def initialize(spec)
          @spec = spec
        end

        attr_reader :spec

        def call
          parts = [creative_block]
          parts << spec.identity.presence
          parts << spec.continuity.presence
          parts << references_block
          parts << spec.on_screen_text.presence
          parts << guardrails_line
          parts.concat(spec.technical_lines)
          parts.compact.map { |p| p.to_s.strip }.reject(&:blank?).join("\n").strip
        end

        private

        # Slots 1–6 (camera + narrative + style + audio), arranged the engine's way.
        def creative_block = raise NotImplementedError, "#{self.class} must implement #creative_block"

        # The visual narrative as a clean sentence (trailing period) so it never
        # runs into the following camera/style clause.
        def narrative_block
          s = spec.narrative.to_s.strip
          return nil if s.empty?

          s.match?(/[.!?:]\z/) ? s : "#{s}."
        end

        # The typed reference manifest — the same contract for every engine (the
        # scene prompt cites the identifiers; this resolves them).
        def references_block
          lines = spec.reference_lines
          return nil if lines.empty?

          "Reference manifest — the attached inputs in order; each has exactly ONE " \
            "job, never blend jobs across references:\n" \
            "#{lines.map { |l| "- #{l}" }.join("\n")}\n" \
            'When this prompt cites an identifier above, follow that reference exactly for ' \
            'its job and nothing else.'
        end

        # Default negatives: an explicit "must NOT contain" list (honored by
        # Seedance/Kling-style engines). Veo overrides with positive phrasing.
        def guardrails_line
          phrases = spec.guardrail_phrases
          return nil if phrases.empty?

          "Hard constraints — the scene must NOT contain any of: #{phrases.join('; ')}."
        end

        # The audio contract lines, joined (already dialect-neutral natural
        # language the engines accept). A dialect may override to relabel.
        def audio_block
          lines = spec.audio_lines
          lines.empty? ? nil : lines.join(' ')
        end
      end
    end
  end
end
