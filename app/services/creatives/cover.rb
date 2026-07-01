# frozen_string_literal: true

module Creatives
  # Profile / page cover artwork. Uploaded only — not generatable.
  class Cover < Base
    def self.type_key = 'cover'

    def self.details
      {
        label: 'Capa',
        width: 1080,
        height: 1080,
        aspect: '1:1',
        generatable: false,
        kind: nil,
        network_fit: %w[instagram facebook linkedin youtube],
        copy_limits: {},
        safe_areas: { top: 64, bottom: 64, left: 64, right: 64 },
        prompt_scaffold: nil
      }
    end
  end
end
