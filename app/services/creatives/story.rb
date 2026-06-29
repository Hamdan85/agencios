# frozen_string_literal: true

module Creatives
  # Full-screen ephemeral story image.
  class Story < Base
    def self.type_key = "story"

    def self.details
      {
        label: "Story",
        width: 1080,
        height: 1920,
        aspect: "9:16",
        generatable: true,
        kind: "image",
        network_fit: %w[instagram facebook],
        copy_limits: { caption: 0, sticker_text: 120 },
        safe_areas: { top: 250, bottom: 250, left: 64, right: 64 },
        prompt_scaffold: "Full-screen 9:16 story. Bold single message, large legible text " \
                         "inside the safe area, space at top and bottom for UI chrome."
      }
    end
  end
end
