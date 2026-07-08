# frozen_string_literal: true

module Operations
  module Video
    # Generates a REFERENCE image (a character sheet or a scenario plate) with
    # Google Banana so a recurring character/scenario stays IDENTICAL across every
    # scene — the orchestrator requests it only when consistency needs an anchor
    # and the user gave no photo of it. Generated once per video, then attached as
    # a typed reference to every scene. Charged as an image generation.
    #
    # Best-effort: a Banana failure refunds the debit and returns nil (the video
    # ships without the generated anchor — never fails the whole render).
    # Returns { url:, role:, prompt: } or nil.
    class GenerateReference < Operations::Base
      ROLES = %w[character scene].freeze

      def initialize(generation:, role:, prompt:, aspect_ratio: nil)
        @generation   = generation
        @role         = ROLES.include?(role.to_s) ? role.to_s : 'character'
        @prompt       = prompt.to_s.strip
        @aspect_ratio = aspect_ratio
      end

      def call
        return nil if @prompt.blank?

        # Charge the image credit up front (raises InsufficientCredits, which the
        # caller catches to simply skip the anchor rather than fail the video).
        Operations::Credits::Debit.call(
          workspace: @generation.workspace, amount: Pricing.credits_for(kind: :image),
          generation: @generation, description: "Referência gerada do vídeo (#{@role})"
        )

        result = begin
          Vendors::Google::Banana::Actions::GenerateImage.call(prompt: full_prompt, aspect_ratio: banana_aspect)
        rescue StandardError => e
          Operations::Credits::Refund.call(generation: @generation)
          Rails.logger.warn("[Video::GenerateReference] #{e.class}: #{e.message}")
          return nil
        end

        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(result[:bytes]), filename: "vidref-#{@generation.id}-#{@role}.jpg",
          content_type: result[:content_type] || 'image/jpeg'
        )
        { url: public_url(blob), role: @role, prompt: @prompt }
      end

      private

      # A clean reference plate: the subject fully in frame on a neutral ground,
      # no lettering/logo (those come from the actual scenes/refs).
      def full_prompt
        "#{@prompt}. A clean reference plate: the subject fully in frame, even neutral lighting, " \
          'plain uncluttered background, high detail, photorealistic. No text, no captions, no logo, no watermark.'
      end

      # A character sheet reads best square; a scenario matches the video frame.
      def banana_aspect
        @role == 'scene' ? (@aspect_ratio.presence || '9:16') : '1:1'
      end

      def public_url(blob)
        Rails.application.routes.url_helpers.rails_blob_url(blob, host: SystemConfig.app_host)
      end
    end
  end
end
