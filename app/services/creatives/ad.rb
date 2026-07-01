# frozen_string_literal: true

module Creatives
  # Square paid-ad creative.
  class Ad < Base
    def self.type_key = 'ad'

    def self.details
      {
        label: 'Anúncio',
        width: 1080,
        height: 1080,
        aspect: '1:1',
        generatable: true,
        kind: 'image',
        network_fit: %w[instagram facebook linkedin],
        copy_limits: { primary_text: 125, headline: 40, description: 30 },
        safe_areas: { top: 64, bottom: 64, left: 64, right: 64 },
        prompt_scaffold: 'Square 1:1 paid ad. Strong value proposition, single product focus, ' \
                         'high contrast, an obvious call to action, minimal text (under 20% area).'
      }
    end
  end
end
