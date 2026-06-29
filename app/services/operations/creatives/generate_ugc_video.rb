# frozen_string_literal: true

module Operations
  module Creatives
    # Kicks off a UGC avatar video render. Produces a Creative (generated, still
    # generating) and a `video` Generation in `processing` — the render is async.
    #
    # A webhook / PollHeygenVideoJob finalizes the Creative + Generation
    # (status completed, asset attached) and meters it via
    # Operations::Billing::RecordUsage. Not yet billed here.
    class GenerateUgcVideo < Operations::Base
      PROVIDER = "heygen"

      def initialize(ticket: nil, script:, avatar: nil, voice: nil)
        @ticket = ticket
        @script = script
        @avatar = avatar
        @voice = voice
      end

      def call
        creative = Operations::Creatives::Create.call(
          ticket: @ticket,
          creative_type: "ugc_video",
          source: :generated,
          status: :generating,
          provider: PROVIDER
        )

        result = Vendors::Heygen::Actions::GenerateVideo.call(
          avatar: @avatar, voice: @voice, script: @script
        )

        generation = workspace.generations.create!(
          user: Current.user,
          creative: creative,
          kind: :video,
          status: :processing,
          provider: PROVIDER,
          external_id: result[:external_id],
          params: { script: @script, avatar: @avatar, voice: @voice }
        )

        broadcast(event: "generation_progress", id: generation.id, kind: "video", status: "processing")
        generation
      end

      private

      def broadcast(payload)
        ActionCable.server.broadcast("generations_#{workspace.id}", payload)
      rescue StandardError
        nil
      end
    end
  end
end
