# frozen_string_literal: true

module Operations
  module Creatives
    # Derives the `image` carousel style's OWN color palette from the client's
    # carousel background photo, using a vision model (Prompts::CarouselPalette +
    # AiAdapter#complete_tool with the image attached). Runs once when the image is
    # set (or on manual re-analyze) — NOT per generation — and persists the result
    # in `clients.carousel_image_palette`, so carousel rendering stays deterministic
    # and never re-calls AI.
    #
    # The palette is kept SEPARATE from brand_primary_color/brand_secondary_color:
    # gradient/white carousels keep using the brand colors; only the image style
    # reads this palette. Cost is logged to AiUsageLog (internal), never debited to
    # the customer's credit wallet — it's a one-time brand-config side effect.
    #
    # Idempotent: keyed on the background blob checksum, so re-running for the same
    # image is a no-op unless `force:` is set.
    class DeriveCarouselPalette < Operations::Base
      OPERATION = 'carousel_palette'
      MIN_CONTRAST = 4.5 # WCAG AA for the on_accent / accent pair.

      def initialize(client:, force: false)
        @client = client
        @force  = force
      end

      def call
        return unless @client.carousel_background.attached?

        blob = @client.carousel_background.blob
        signature = blob.checksum
        return if !@force && @client.carousel_image_palette['source_signature'] == signature

        raw = AiAdapter.complete_tool(
          Prompts::CarouselPalette.new(client: @client, workspace: @client.workspace),
          tool: Prompts::CarouselPalette::TOOL,
          image: { bytes: blob.download, content_type: blob.content_type },
          operation: OPERATION,
          subject: @client
        )
        return if raw.blank? # offline stub / model didn't call the tool — leave brand-color fallback.

        palette = guard(raw).merge('source_signature' => signature, 'derived_at' => Time.current.iso8601)
        @client.update!(carousel_image_palette: palette)
        @client
      end

      private

      # Coerce the model output into a safe, self-consistent palette. A malformed
      # hex from the model clamps to a sane default rather than 500-ing an upload;
      # on_accent is forced to a readable value if its contrast against accent fails.
      # Every fallback stays inside the client's brand (accent → brand secondary,
      # scrim → a dark tint of the brand primary), so a degraded model response
      # still yields a branded carousel rather than a generic black-on-white one.
      def guard(raw)
        accent      = hex(raw['accent'], fallback: brand_secondary)
        text_color  = hex(raw['text_color'], fallback: '#FFFFFF')
        scrim       = hex(raw['scrim_color'], fallback: brand_scrim)
        opacity     = raw['scrim_opacity'].to_f.clamp(0.0, 0.6)
        on_accent   = readable_on(accent, hex(raw['on_accent'], fallback: '#FFFFFF'))
        text_shadow = shadow(raw['text_shadow'])

        {
          'accent' => accent, 'on_accent' => on_accent, 'text_color' => text_color,
          'scrim_color' => scrim, 'scrim_opacity' => opacity, 'text_shadow' => text_shadow,
          'reasoning' => raw['reasoning'].to_s.strip.presence
        }.compact
      end

      # The shadow is the cheap legibility lever (it leaves the photo untouched), so an
      # unrecognized value falls back to `soft` — the safe middle — never to `none`.
      def shadow(value)
        str = value.to_s.strip.downcase
        Prompts::CarouselPalette::TEXT_SHADOWS.include?(str) ? str : 'soft'
      end

      # A very dark tint of the brand primary — the default scrim when the model gives
      # us nothing usable. Beats pure black: it dims the photo without washing the
      # brand out of it.
      def brand_scrim
        darken(@client.brand_primary_color.presence || '#7C3AED', 0.28)
      end

      # Scale every channel toward black, which PRESERVES the hue. (Subtracting a
      # constant instead — the CSS-gradient `shade` the template uses — bottoms the
      # weak channels out first and swings the hue: #7C3AED would land on navy, not
      # dark purple.) `factor` is the fraction of the original brightness kept.
      def darken(hex, factor)
        match = hex.to_s.strip.match(/\A#?([0-9a-fA-F]{6})\z/)
        return '#000000' unless match

        rgb = match[1].scan(/../).map { |c| (c.to_i(16) * factor).round.clamp(0, 255) }
        format('#%02x%02x%02x', *rgb)
      end

      # Keep the model's on_accent when it's legible over accent; otherwise pick
      # whichever of white/black gives the higher contrast.
      def readable_on(accent, candidate)
        return candidate if contrast(candidate, accent) >= MIN_CONTRAST

        contrast('#FFFFFF', accent) >= contrast('#111111', accent) ? '#FFFFFF' : '#111111'
      end

      def brand_secondary
        @client.brand_secondary_color.presence || '#F59E0B'
      end

      def hex(value, fallback:)
        str = value.to_s.strip
        str.match?(/\A#[0-9a-fA-F]{6}\z/) ? str.downcase : fallback
      end

      # WCAG contrast ratio between two #rrggbb colors.
      def contrast(a, b)
        la = luminance(a)
        lb = luminance(b)
        hi = [la, lb].max
        lo = [la, lb].min
        (hi + 0.05) / (lo + 0.05)
      end

      def luminance(hex)
        rgb = hex.delete_prefix('#').scan(/../).map do |c|
          v = c.to_i(16) / 255.0
          v <= 0.03928 ? v / 12.92 : (((v + 0.055) / 1.055)**2.4)
        end
        (0.2126 * rgb[0]) + (0.7152 * rgb[1]) + (0.0722 * rgb[2])
      end
    end
  end
end
