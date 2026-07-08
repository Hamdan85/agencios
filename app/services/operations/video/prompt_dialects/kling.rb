# frozen_string_literal: true

module Operations
  module Video
    module PromptDialects
      # Kwaivgi Kling 3.x — structured natural language, written CAMERA-FIRST like
      # scene direction: ground the camera behaviour, then the scene, then the
      # subject and its action (Kling integrates camera and subject motion in one
      # description rather than separating them). Kling historically routes negatives
      # through a SEPARATE negative-prompt field; until that field is wired through
      # the vendor we emit a compact in-prompt "Avoid:" clause as a best-effort.
      class Kling < Base
        private

        def creative_block
          [
            i2v_lead,
            "Camera: #{spec.camera}.",               # camera-first
            narrative_block,
            spec.style_fence.to_s.strip.presence,
            audio_block
          ].compact.reject(&:blank?).join(' ')
        end

        # NOTE: Kling's robust path is a separate negative-prompt field (not yet
        # wired through Vendors::OpenRouter::Video). In-prompt avoid is best-effort.
        def guardrails_line
          phrases = spec.guardrail_phrases
          return nil if phrases.empty?

          "Avoid: #{phrases.join('; ')}."
        end

        I2V_LEAD =
          'Treat the provided image as the anchor: describe how the scene EVOLVES from ' \
          'it — subtle motion, camera movement, environmental change — never re-describing ' \
          'the still. Preserve the subject, text/signage, product and layout from the image.'
        def i2v_lead = spec.i2v? ? I2V_LEAD : nil
      end
    end
  end
end
