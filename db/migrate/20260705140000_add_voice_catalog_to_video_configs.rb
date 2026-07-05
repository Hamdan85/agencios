# frozen_string_literal: true

# Consistent voice: an admin-managed catalog of Cartesia voices (label → voice_id)
# + a default, and a toggle to dub the fixed voice in post (ffmpeg) instead of
# relying on the render model to lip-sync to the audio reference.
class AddVoiceCatalogToVideoConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :video_configs, :voice_catalog, :jsonb, default: {}, null: false
    add_column :video_configs, :default_voice_id, :string
    add_column :video_configs, :voice_dub_in_post, :boolean, default: false, null: false
  end
end
