# frozen_string_literal: true

module Operations
  module Video
    module PromptDialects
      # Fallback for an unknown/unlisted engine — the Veo cinematic-paragraph
      # dialect, which is the safest general-purpose shape (rich, positive, camera-led).
      class Default < Veo
      end
    end
  end
end
