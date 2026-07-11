# frozen_string_literal: true

module Controllers
  module VideoScenes
    # POST /creatives/:creative_id/assets/regenerate — regenerate ONE asset from a
    # new prompt. Guests cannot edit; regenerating a character/scenario spends an
    # image credit (billing-gated → 402 when the wallet can't cover it). Music is
    # a free re-search + re-mix.
    #   body { type: 'character' | 'scene' | 'music', prompt, ref_url? }
    class RegenerateAsset < Base
      TYPES = %w[character scene music].freeze

      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        require_billing!
        creative = workspace.creatives.find(@params[:creative_id])

        raise Operations::Errors::Invalid, I18n.t('api.video.invalid_asset_type') unless TYPES.include?(type)
        type == 'music' ? regenerate_music(creative) : regenerate_reference(creative)

        creative.reload
        {
          assets: Operations::Video::AssetList.call(creative: creative),
          creative: serialize(creative, CreativeSerializer)
        }
      end

      private

      def type   = @params[:type].to_s
      def prompt = @params[:prompt].to_s

      def regenerate_reference(creative)
        Operations::Video::RegenerateReference.call(
          creative: creative, role: type, prompt: prompt, replace_url: @params[:ref_url]
        )
      end

      # Re-search the active provider with the prompt as the query and re-mix — no
      # re-render, no credits (mirrors the chat's "change music").
      def regenerate_music(creative)
        Operations::Video::ChangeMusic.call(creative: creative, query: prompt)
      end
    end
  end
end
