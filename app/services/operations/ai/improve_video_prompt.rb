# frozen_string_literal: true

module Operations
  module Ai
    # One-shot "melhorar esse prompt": rewrites the user's draft video prompt
    # with the full generation context (brand, positioning, mode, format, voice,
    # identity assets). Returns the improved PT-BR prompt string — the dialog
    # streams it back into the input field. Any AI failure surfaces as a clean
    # Invalid (422) so the frontend restores the draft.
    class ImproveVideoPrompt < Operations::Base
      MAX_TOKENS = 1000

      def initialize(workspace:, user:, mode:, prompt:, client: nil,
                     aspect_ratio: nil, duration: nil, with_audio: true, voice: nil,
                     reference_count: 0, max_chars: 1200)
        @workspace = workspace
        @user      = user
        @client    = client
        @mode      = mode.to_s == 'product' ? 'product' : 'avatar'
        @prompt    = prompt.to_s.strip
        @aspect    = aspect_ratio
        @duration  = duration
        @audio     = with_audio.nil? ? true : ActiveModel::Type::Boolean.new.cast(with_audio)
        @voice     = voice
        @ref_count = reference_count.to_i
        @max_chars = max_chars.to_i
      end

      def call
        improver = Prompts::VideoPromptImprover.new(
          workspace: @workspace, client: @client, mode: @mode,
          aspect_ratio: @aspect, duration: @duration, with_audio: @audio,
          voice: @voice, reference_count: @ref_count,
          has_logo: @mode == 'product' && ctx.brand_logo_url.present?,
          has_avatar: @mode == 'avatar' && ctx.brand_avatar_url.present?,
          max_chars: @max_chars
        )
        ai = Vendors::Ai.client(model: Vendors::Ai.model_for('improve_video_prompt'))
        result = ai.generate(
          system: improver.system,
          prompt: "User's current prompt draft:\n#{@prompt}\n\nRewrite it now by calling the tool.",
          tool: Prompts::VideoPromptImprover.improve_tool,
          max_tokens: MAX_TOKENS
        )
        log_usage(result, ai)

        improved = result.tool_input.is_a?(Hash) ? result.tool_input['prompt'].to_s.strip : ''
        raise Operations::Errors::Invalid, FAILURE_MESSAGE if improved.blank?

        improved[0, @max_chars]
      rescue Operations::Errors::Invalid
        raise
      rescue StandardError => e
        Rails.logger.warn("[Ai::ImproveVideoPrompt] #{e.class}: #{e.message}")
        raise Operations::Errors::Invalid, FAILURE_MESSAGE
      end

      FAILURE_MESSAGE = 'Não foi possível melhorar o prompt agora — tente de novo.'

      private

      # The same identity truth the renderer uses (raster-only logo/avatar URLs).
      def ctx
        @ctx ||= ::Tickets::CreativeContext.for(nil, creative_type: 'ugc_video', client: @client)
      end

      def log_usage(result, ai)
        Operations::Ai::LogUsage.call(
          provider: ai.provider_key, operation: 'improve_video_prompt', model: result.model,
          usage: result.usage,
          cost_cents: result.usage.is_a?(Hash) ? result.usage['cost_cents'] : nil,
          subject: @client, workspace: @workspace, user: @user
        )
      rescue StandardError
        nil
      end
    end
  end
end
