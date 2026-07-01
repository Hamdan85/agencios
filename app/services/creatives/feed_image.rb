# frozen_string_literal: true

module Creatives
  # Single static feed image (portrait 4:5, the highest-reach feed ratio).
  class FeedImage < Base
    def self.type_key = 'feed_image'

    def self.details
      {
        label: 'Imagem de feed',
        width: 1080,
        height: 1350,
        aspect: '4:5',
        generatable: true,
        kind: 'image',
        network_fit: %w[instagram facebook linkedin],
        copy_limits: { caption: 2200, hashtags: 30 },
        safe_areas: { top: 96, bottom: 96, left: 64, right: 64 },
        prompt_scaffold: 'Single portrait 4:5 feed image. One subject, brand colors, ' \
                         'clear focal point, room for an overlaid headline.'
      }
    end
  end
end
