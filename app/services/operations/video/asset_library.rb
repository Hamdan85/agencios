# frozen_string_literal: true

module Operations
  module Video
    # The library of reusable elements the user can ADD to a video (besides an
    # upload): the workspace/client BRAND assets (avatar, logo) and the CHARACTERS
    # and SCENARIOS already used in the workspace's OTHER videos — so a mascot or a
    # signature setting can be reused across videos. Read-only.
    class AssetLibrary < Operations::Base
      REUSABLE_ROLES = %w[character scene].freeze
      SCENES_SCANNED = 200
      MAX_ITEMS = 24

      def initialize(creative:)
        @creative = creative
      end

      def call
        { items: (brand_items + reused_items).uniq { |i| i[:url] }.first(MAX_ITEMS) }
      end

      private

      # The brand's spokesperson + mark, typed so a click adds them under the right
      # role. Best-effort: no ticket / no context → just the reused items.
      def brand_items
        ctx = context
        return [] unless ctx

        [
          { url: ctx.brand_avatar_url, role: 'avatar', label: I18n.t('operations.video.library.brand_avatar'), kind: 'img' },
          { url: ctx.brand_logo_url, role: 'logo', label: I18n.t('operations.video.library.brand_logo'), kind: 'img' }
        ].select { |i| i[:url].present? }
      rescue StandardError
        []
      end

      # Distinct character/scenario reference images from the workspace's OTHER
      # videos (most recent first), so they can be reused here.
      def reused_items
        scenes = VideoScene.where(workspace_id: @creative.workspace_id)
                           .where.not(creative_id: @creative.id)
                           .order(created_at: :desc).limit(SCENES_SCANNED)

        seen = Set.new
        scenes.flat_map(&:labeled_references).filter_map do |r|
          url = r[:url].to_s
          next unless REUSABLE_ROLES.include?(r[:role].to_s) && url.present? && seen.add?(url)

          { url: url, role: r[:role].to_s, kind: r[:kind],
            label: I18n.t("operations.video.roles.#{r[:role].to_s == 'character' ? 'character' : 'scene'}") }
        end
      end

      def context
        ::Tickets::CreativeContext.for(
          @creative.ticket, creative_type: @creative.creative_type,
          client: client
        )
      end

      def client
        id = @creative.generation&.params&.dig('client_id')
        id.present? ? @creative.workspace.clients.find_by(id: id) : nil
      end
    end
  end
end
