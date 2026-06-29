# frozen_string_literal: true

module Creatives
  # Short-form vertical video (Reels / TikTok / Shorts).
  class Reel < Base
    def self.type_key = "reel"

    def self.details
      {
        label: "Reel",
        width: 1080,
        height: 1920,
        aspect: "9:16",
        generatable: true,
        kind: "video",
        network_fit: %w[instagram tiktok youtube],
        copy_limits: { caption: 2200, hashtags: 30 },
        safe_areas: { top: 220, bottom: 320, left: 64, right: 180 },
        prompt_scaffold: "Vertical 9:16 short-form video. Hook in the first 2 seconds, " \
                         "fast-paced cuts, captions on screen, single clear payoff."
      }
    end
  end
end
