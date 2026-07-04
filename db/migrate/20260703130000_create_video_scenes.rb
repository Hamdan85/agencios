# frozen_string_literal: true

# A video is a sequence of scenes. Each scene is an independently-rendered clip
# (its own OpenRouter job + seed) so a small edit re-renders ONE scene, not the
# whole video. The final video Creative is the ffmpeg concat of its ready scenes.
class CreateVideoScenes < ActiveRecord::Migration[8.1]
  def change
    create_table :video_scenes do |t|
      t.references :workspace, null: false, foreign_key: true, index: true
      t.references :creative,  null: false, foreign_key: true, index: true
      t.integer :position, null: false, default: 0
      t.string  :mode                                    # avatar | product
      t.text    :prompt                                  # what this scene renders
      t.text    :caption                                 # on-screen caption (free overlay edit)
      t.string  :seed                                    # reused on re-render for consistency
      t.string  :external_id                             # OpenRouter job id
      t.integer :render_state, null: false, default: 0   # fresh/rendering/ready/failed/stale
      t.integer :duration_seconds
      t.string  :aspect_ratio
      t.jsonb   :reference_image_urls, null: false, default: []
      t.integer :cost_cents
      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :video_scenes, %i[creative_id position]
  end
end
