# frozen_string_literal: true

module Creatives
  # Video thumbnail / cover frame (16:9, YouTube-fit).
  class Thumbnail < Base
    def self.type_key = "thumbnail"

    def self.details
      {
        label: "Thumbnail",
        width: 1280,
        height: 720,
        aspect: "16:9",
        generatable: true,
        kind: "image",
        network_fit: %w[youtube],
        copy_limits: { overlay_text: 40 },
        safe_areas: { top: 48, bottom: 48, left: 48, right: 48 },
        prompt_scaffold: "16:9 video thumbnail. One expressive subject, punchy 3-4 word overlay, " \
                         "saturated colors, high contrast, readable at small sizes."
      }
    end
  end
end
