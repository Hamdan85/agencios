# frozen_string_literal: true

module Operations
  module Video
    module PromptDialects
      # Google Veo 3.x — a rich cinematic PARAGRAPH in director-briefing style,
      # led by the cinematography (camera + shot + lens), then subject/action/
      # setting/style flowing together. Veo's official guidance is to phrase
      # exclusions POSITIVELY (it ignores negation words), so guardrails are
      # rendered as a "free of …" clause rather than a "must not" list.
      class Veo < Base
        private

        def creative_block
          [
            i2v_lead,
            "#{spec.camera}.",                       # cinematography leads the paragraph
            narrative_block,
            spec.style_fence.to_s.strip.presence,
            audio_block
          ].compact.reject(&:blank?).join(' ')
        end

        # Veo ignores "no X" — state exclusions positively so they still land.
        def guardrails_line
          phrases = spec.guardrail_phrases
          return nil if phrases.empty?

          "Keep the scene entirely free of #{phrases.join(', ')} — none of these appear anywhere in frame."
        end

        I2V_LEAD =
          'Animate the provided image: describe only the motion, transition and change — ' \
          'do not re-describe what is already shown. The subject, wardrobe, product, logo ' \
          'and framing stay exactly as in the image.'
        def i2v_lead = spec.i2v? ? I2V_LEAD : nil
      end
    end
  end
end
