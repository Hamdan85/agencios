# frozen_string_literal: true

module Prompts
  # Rewrites the user's draft VIDEO GENERATION prompt into a sharper, more
  # filmable brief — the "melhorar esse prompt" wand in the generate dialog. It
  # carries the full generation context (brand, positioning, mode, format,
  # duration, sound, voice, identity assets) so the improved prompt is written
  # for THIS client and THIS setup, not generically.
  #
  # System/tool text is ENGLISH (code); the improved prompt itself is produced
  # in the response language — it lands back in the user's input field as editable content.
  #
  # Context keys: mode ('avatar' | 'product'), aspect_ratio, duration,
  # with_audio (bool), voice, reference_count (int), has_logo (bool),
  # has_avatar (bool), max_chars (int).
  class VideoPromptImprover < Base
    IMPROVE_TOOL = 'improved_prompt'

    VOICE_TONES = {
      'pt_br_warm'      => 'warm and friendly',
      'pt_br_energetic' => 'energetic and upbeat',
      'pt_br_pro'       => 'professional and confident'
    }.freeze

    def system
      <<~TXT.strip
        You are a senior creative director at a social media agency. Rewrite the
        user's draft brief for an AI VIDEO GENERATION into a sharper, more
        filmable prompt.

        #{brand_block}

        #{positioning_block}

        Video setup:
        #{setup_block}

        Rules:
        - KEEP the user's core idea and intent — sharpen it, never replace it.
          Where the draft is vague, make the choices concrete: setting, subject,
          action, mood, pacing, camera feel.
        - #{mode_rule}
        - The brand block and positioning above are BACKGROUND CONTEXT: use them
          to guide tone and content choices — never transcribe them into the
          prompt as lines to be spoken or shown, and never invent claims, prices
          or features.
        - On-screen text: only suggest it when it is short, real and correctly
          spelled — otherwise suggest none.
        - Write the improved prompt in #{response_language} — it goes back into
          the user's input field as editable text.
        - At most #{context[:max_chars].to_i} characters. No headings, no bullet
          lists, no surrounding quotes — just the prompt text, 1–3 short
          paragraphs.

        Call the tool with the improved prompt.
      TXT
    end

    def self.improve_tool
      {
        'name' => IMPROVE_TOOL,
        'description' => 'Returns the improved video generation prompt.',
        'input_schema' => {
          'type' => 'object', 'required' => %w[prompt],
          'properties' => {
            'prompt' => {
              'type' => 'string',
              'description' => 'The improved prompt, in the response language set in the system prompt, ready to replace the draft.'
            }
          }
        }
      }
    end

    private

    def setup_block
      lines = []
      lines << if context[:mode].to_s == 'product'
                 '- Mode: PRODUCT — a product clip generated from reference photos.'
               else
                 '- Mode: AVATAR — a real person talking to camera (authentic UGC).'
               end
      lines << "- Format #{context[:aspect_ratio].presence || '9:16'} · target duration ~#{context[:duration].to_i}s " \
               '(renders as continuous ~8s scenes).'
      lines << (context[:with_audio] ? '- Sound: native speech and ambient audio.' : '- Sound: silent video (no speech).')
      if context[:mode].to_s != 'product' && (tone = VOICE_TONES[context[:voice].to_s])
        lines << "- Voice tone: #{tone}."
      end
      assets = renderer_assets
      lines << "- Assets the renderer receives: #{assets.join(', ')}." if assets.any?
      lines.join("\n")
    end

    def renderer_assets
      assets = []
      assets << "#{context[:reference_count].to_i} product reference photo(s)" if context[:reference_count].to_i.positive?
      assets << 'the brand logo' if context[:has_logo]
      assets << 'the creator avatar (the on-camera face)' if context[:has_avatar]
      assets
    end

    def mode_rule
      if context[:mode].to_s == 'product'
        'PRODUCT mode: describe shots that sell — angles, motion, environment; ' \
          'the product must stay faithful to the reference photos.'
      else
        'AVATAR mode: include what the person SAYS — short, natural spoken ' \
          'lines that fit the duration.'
      end
    end
  end
end
