# frozen_string_literal: true

module Controllers
  module VideoScenes
    # POST /creatives/:creative_id/video_chat — one turn of the conversational
    # video editor. Guests cannot edit; editing can spend credits, so it's
    # billing-gated (a reply-only turn is free — the per-scene debit happens inside
    # EditScene only when a scene is actually re-rendered).
    class Chat < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        creative = workspace.creatives.find(@params[:creative_id])

        result = Operations::Video::Chat::ResolveTurn.call(
          creative: creative, message: message, reference_image_urls: reference_image_urls,
          reference_descriptions: reference_descriptions, annotations: annotations
        )
        creative.reload

        {
          reply: result[:reply],
          action: result[:action],
          # 1-based scene numbers this turn started working on, so the UI can
          # immediately point the user at the scenes being re-rendered.
          working_scenes: Array(result[:edited_positions]).map { |p| p + 1 },
          # Credits this turn spent (0 when nothing re-rendered) — the ledger
          # holds the per-scene debits; this is the turn total for the UI.
          credits_spent: result[:credits_spent].to_i,
          creative: serialize(creative, CreativeSerializer),
          messages: creative.chat_messages,
          scenes: serialize_collection(creative.video_scenes.ordered, VideoSceneSerializer)
        }
      end

      private

      def message
        raw = @params[:message] || @params.dig(:chat, :message)
        raw.to_s
      end

      # Media references the user attached this turn (already-uploaded public
      # URLs from the uploads endpoint).
      def reference_image_urls
        Array(@params[:reference_image_urls]).map { |u| u.to_s.strip }.reject(&:blank?)
      end

      # Parallel to reference_image_urls — the user's own words for each file
      # ("what is this document?"), so the orchestrator uses it as intended.
      def reference_descriptions
        Array(@params[:reference_descriptions]).map { |d| d.to_s }
      end

      # Structured per-scene notes from the UI balloons:
      # [{ scene: <1-based number>, note: <text> }] — validated in ResolveTurn.
      def annotations
        Array(@params[:annotations])
      end
    end
  end
end
