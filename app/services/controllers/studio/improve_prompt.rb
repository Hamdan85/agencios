# frozen_string_literal: true

module Controllers
  module Studio
    # POST /studio/improve_prompt — the "melhorar esse prompt" wand of the
    # generate dialog: rewrites the user's draft video prompt with the full
    # brand/setup context. Text-AI only (no credits), but billing-gated like
    # every generation surface; guests cannot use it.
    class ImprovePrompt < Base
      # Server-side output caps per mode — mirror the dialog's input limits
      # (avatar script 1200 / product brief 1000); never trust a client number.
      MAX_CHARS = { 'avatar' => 1200, 'product' => 1000 }.freeze

      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!

        prompt = @params[:prompt].to_s.strip
        raise Operations::Errors::Invalid, 'Escreva um rascunho do prompt primeiro.' if prompt.blank?

        mode = @params[:mode].to_s == 'product' ? 'product' : 'avatar'
        improved = Operations::Ai::ImproveVideoPrompt.call(
          workspace: workspace, user: user,
          client: workspace.clients.find_by(id: @params[:client_id]),
          mode: mode, prompt: prompt,
          aspect_ratio: @params[:aspect_ratio], duration: @params[:duration],
          with_audio: @params[:with_audio], voice: @params[:voice],
          reference_count: @params[:reference_count],
          max_chars: MAX_CHARS.fetch(mode)
        )
        { prompt: improved }
      end
    end
  end
end
