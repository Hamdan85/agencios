# frozen_string_literal: true

module Operations
  module Video
    module Scenes
      # Creates one VideoScene on a creative (fresh, not yet rendered). Called by
      # the video pipeline instead of a bare create! (per the reuse convention).
      # dialogue / on_screen_text are the scene's exact spoken line and lettering
      # (PT-BR) — first-class creative fields, stored in metadata and compiled
      # into the render prompt by DecoratePrompt.
      class Create < Operations::Base
        def initialize(creative:, position:, mode:, prompt:, caption: nil, duration_seconds: nil,
                       aspect_ratio: nil, seed: nil, reference_image_urls: [], reference_roles: [],
                       reference_descriptions: [], camera: nil, dialogue: nil, sound_effects: nil,
                       on_screen_text: nil, continues_previous: nil)
          @creative = creative
          @metadata = {
            # The isolated cinematography slot (one dominant camera move + framing).
            'camera' => camera.to_s.strip.presence,
            'dialogue' => dialogue.to_s.strip.presence,
            # Diegetic sound the model GENERATES for this scene (explosions, steps…);
            # blank = no model-generated sound. Music is never here (post track).
            'sound_effects' => sound_effects.to_s.strip.presence,
            'on_screen_text' => on_screen_text.to_s.strip.presence,
            'reference_roles' => Array(reference_roles).map(&:to_s).presence,
            # The user's own words for each reference ("what is this file?"),
            # parallel to reference_image_urls — carried into the render manifest.
            'reference_descriptions' => Array(reference_descriptions).map(&:to_s).presence,
            # false marks a CUT (a new shot, not seeded by the previous frame).
            'continues_previous' => continues_previous.nil? ? nil : (continues_previous != false)
          }.compact
          @attrs = {
            position: position, mode: mode.to_s, prompt: prompt, caption: caption,
            duration_seconds: duration_seconds, aspect_ratio: aspect_ratio, seed: seed,
            reference_image_urls: Array(reference_image_urls)
          }
        end

        def call
          @creative.video_scenes.create!(workspace: @creative.workspace, render_state: :fresh,
                                         metadata: @metadata, **@attrs)
        end
      end
    end
  end
end
