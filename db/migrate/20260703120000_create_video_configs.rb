# frozen_string_literal: true

# Singleton config for the video-generation engine routing (admin-editable, no
# deploy). Mirrors ai_configs: the API key stays in credentials; only the
# non-secret provider choice + per-mode model slugs + limits live here.
class CreateVideoConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :video_configs do |t|
      t.string  :provider                                   # '' (auto) | 'openrouter'
      t.string  :default_model                              # fallback OpenRouter video slug
      t.jsonb   :mode_models, default: {}, null: false      # { "avatar" => slug, "product" => slug }
      t.integer :max_duration_seconds, default: 30, null: false
      t.timestamps
    end
  end
end
