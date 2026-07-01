# frozen_string_literal: true

module Creatives
  # User-generated-content style talking-head video (HeyGen / HyperFrames avatar).
  # Metered as a `video` generation.
  class UgcVideo < Base
    def self.type_key = 'ugc_video'

    def self.details
      {
        label: 'Vídeo UGC',
        width: 1080,
        height: 1920,
        aspect: '9:16',
        generatable: true,
        kind: 'video',
        provider: 'heygen',
        network_fit: %w[instagram tiktok youtube],
        copy_limits: { caption: 2200, script: 1200 },
        safe_areas: { top: 220, bottom: 320, left: 64, right: 180 },
        prompt_scaffold: 'Authentic UGC talking-head. Casual first-person delivery, ' \
                         'selfie framing, natural lighting, an avatar reading the script verbatim.'
      }
    end
  end
end
