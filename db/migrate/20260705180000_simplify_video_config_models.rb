# frozen_string_literal: true

# Collapse the video engine routing to exactly TWO models: one DRAFT (fast/cheap
# preview) and one FINAL (`default_model`). The per-mode maps are gone — the
# platform no longer routes the model by generation mode, only by quality tier.
class SimplifyVideoConfigModels < ActiveRecord::Migration[8.1]
  def up
    add_column :video_configs, :draft_model, :string

    # Preserve a sensible draft slug from the old per-mode map (avatar first).
    execute <<~SQL.squish
      UPDATE video_configs
      SET draft_model = COALESCE(
        NULLIF(draft_models->>'avatar', ''),
        NULLIF(draft_models->>'product', '')
      )
      WHERE draft_model IS NULL
    SQL

    remove_column :video_configs, :mode_models
    remove_column :video_configs, :draft_models
  end

  def down
    add_column :video_configs, :mode_models, :jsonb, null: false, default: {}
    add_column :video_configs, :draft_models, :jsonb, null: false, default: {}
    remove_column :video_configs, :draft_model
  end
end
