# frozen_string_literal: true

module Creatives
  # Multi-slide carousel (swipeable post). Metered as a `carousel` generation.
  class Carousel < Base
    def self.type_key = 'carousel'

    def self.details
      {
        label: 'Carrossel',
        width: 1080,
        height: 1350,
        aspect: '4:5',
        generatable: true,
        kind: 'carousel',
        min_slides: 3,
        max_slides: 10,
        network_fit: %w[instagram linkedin facebook],
        copy_limits: { caption: 2200, headline_per_slide: 60 },
        safe_areas: { top: 120, bottom: 160, left: 64, right: 64 },
        prompt_scaffold: 'Cohesive swipeable carousel. Slide 1 is the hook, middle slides ' \
                         'deliver one point each, last slide is the call to action. ' \
                         'Consistent brand identity, @handle and avatar on every slide.'
      }
    end
  end
end
