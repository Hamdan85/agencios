# frozen_string_literal: true

module Operations
  module Video
    # The ELEMENTS of a generated video, for the editor's "Elementos" tab: the
    # recurring CHARACTERS, the SCENARIOS, any other typed REFERENCES fed to the
    # render (product, logo, style, camera, motion…), and the background MUSIC.
    # Read-only derivation — the source of truth is the generation params
    # (identity + music + stored descriptions) and the scenes' typed references.
    class AssetList < Operations::Base
      # How the render roles map onto the tab's groups (order = display order).
      GROUPS = {
        characters: %w[character avatar],
        scenarios: %w[scene],
        references: %w[product logo style camera motion reference]
      }.freeze

      # Roles that carry a locked-identity TEXT description (so an image-less video
      # still lists a regeneratable character/scenario).
      IDENTITY_FIELD = { 'character' => 'character', 'scene' => 'scenario' }.freeze

      def initialize(creative:)
        @creative = creative
      end

      def call
        by_url = references_by_url
        {
          characters: group(:characters, by_url),
          scenarios: group(:scenarios, by_url),
          references: group(:references, by_url),
          music: music
        }
      end

      private

      def identity = @creative.generation&.params&.dig('identity') || {}

      # Stored per-asset descriptions (PT), keyed by URL or "identity:<field>".
      def descriptions = @creative.generation&.params&.dig('asset_descriptions') || {}

      # Every distinct reference across the scenes, keyed by URL, with its role +
      # media kind (first occurrence wins — stored order is the submitted order).
      def references_by_url
        @creative.video_scenes.flat_map(&:labeled_references).each_with_object({}) do |r, acc|
          url = r[:url].to_s
          next if url.blank? || acc.key?(url)

          acc[url] = { role: r[:role].to_s, kind: r[:kind] }
        end
      end

      # The assets of one group: every stored reference whose role belongs to it,
      # plus a text-only identity asset when the role is described but has no image.
      def group(name, by_url)
        roles = GROUPS.fetch(name)
        items = by_url.filter_map do |url, ref|
          next unless roles.include?(ref[:role])

          asset(key: url, role: ref[:role], image_url: url, kind: ref[:kind])
        end

        roles.each do |role|
          field = IDENTITY_FIELD[role]
          next unless field && identity[field].present? && items.none? { |i| i[:role] == role }

          items << asset(key: "identity:#{field}", role: role, image_url: nil, kind: nil)
        end
        items
      end

      def asset(key:, role:, image_url:, kind:)
        {
          key: key, role: role, role_label: role_label(role),
          image_url: image_url, kind: kind, description: description_for(key, role)
        }
      end

      # User-facing role label (display copy). Runs in-request, so the requester's
      # locale is already set. Falls back to the raw role for unknown keys.
      def role_label(role)
        key = "operations.video.roles.#{role}"
        I18n.exists?(key) ? I18n.t(key) : role
      end

      # A stored PT description wins; else the locked-identity text for the role.
      def description_for(key, role)
        return descriptions[key] if descriptions[key].present?

        field = IDENTITY_FIELD[role]
        field ? identity[field].to_s.strip.presence : nil
      end

      # The chosen soundtrack (mood + credit + burnable URL), or nil when the
      # video has none (silent, or the provider found nothing).
      def music
        params = @creative.generation&.params || {}
        return nil if params['music_url'].blank?

        {
          mood: params['music_mood'],
          title: params['music_title'],
          attribution: params['music_attribution'],
          url: params['music_url']
        }.compact
      end
    end
  end
end
