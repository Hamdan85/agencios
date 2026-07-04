# frozen_string_literal: true

class AddDraftModelsToVideoConfigs < ActiveRecord::Migration[8.1]
  def change
    # Per-mode DRAFT engine slugs (fast/cheap preview models). The final-quality
    # slugs stay in `mode_models`; a generation renders draft-first and upgrades
    # on approval.
    add_column :video_configs, :draft_models, :jsonb, null: false, default: {}
  end
end
