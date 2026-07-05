# frozen_string_literal: true

module Controllers
  module Studio
    # POST /studio/video — opens a video as a CHAT INTERVIEW instead of generating
    # immediately: creates a draft creative + the agent's first question. No
    # generation, no credit hold yet (the chat's "generate" action does that once
    # it has enough context). Billing-gated; guests cannot start one.
    class StartVideo < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        p = generation_params

        creative = Operations::Video::StartInterview.call(
          workspace: workspace, client_id: p[:client_id], mode: p[:mode],
          prompt: p[:prompt], voice: p[:voice], aspect_ratio: p[:aspect_ratio],
          duration: p[:duration], with_audio: p.fetch(:with_audio, true),
          reference_image_urls: p.fetch(:reference_image_urls, [])
        )
        { creative: serialize(creative, CreativeSerializer), messages: creative.chat_messages }
      end

      private

      def generation_params
        raw = @params[:params]
        return {} if raw.blank?

        raw.permit!.to_h.symbolize_keys
      end
    end
  end
end
