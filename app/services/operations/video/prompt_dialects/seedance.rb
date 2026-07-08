# frozen_string_literal: true

module Operations
  module Video
    module PromptDialects
      # ByteDance Seedance 2.0 — our PRIMARY engine. Documented preference: a
      # concise flowing description that LEADS with subject + action, with the
      # camera as its OWN separate clause (Seedance is explicit that tangling camera
      # motion and subject motion in one clause is the top cause of unstable output),
      # one dominant camera move phrased in plain pacing words, then style, then an
      # in-prompt "Avoid:" clause for negatives.
      class Seedance < Base
        private

        def creative_block
          [
            i2v_lead,
            narrative_block,
            "Camera: #{spec.camera}.",              # its own clause, one dominant move
            spec.style_fence.to_s.strip.presence,
            audio_block
          ].compact.reject(&:blank?).join(' ')
        end

        # Seedance honors an explicit in-prompt avoid clause.
        def guardrails_line
          phrases = spec.guardrail_phrases
          return nil if phrases.empty?

          "Avoid (must NOT appear or happen): #{phrases.join('; ')}."
        end

        # "Animate the frame, motion only" — Seedance I2V guidance: describe the
        # change, preserve composition and colors.
        I2V_LEAD =
          'Animate the provided reference frame — describe ONLY the motion and change, ' \
          'not what is already visible. Preserve composition, colors, identity, product ' \
          'and layout exactly as in the frame.'
        def i2v_lead = spec.i2v? ? I2V_LEAD : nil
      end
    end
  end
end
