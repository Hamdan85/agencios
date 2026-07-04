# frozen_string_literal: true

# Royalty-free background-music catalog for video generation: mood → track. The
# video model never generates music; the storyboard picks a MOOD and the compose
# step burns the matching track (from this admin-managed base) under the audio.
class AddMusicTracksToVideoConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :video_configs, :music_tracks, :jsonb, default: {}, null: false
  end
end
