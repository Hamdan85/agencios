# frozen_string_literal: true

# The active background-music provider for video generation — an admin-editable
# adapter switch (no deploy). Every provider exposes the same search contract
# (Vendors::Music); Jamendo (royalty-free) is the default, Epidemic Sound is an
# alternative once its API account has download entitlement.
class AddMusicProviderToVideoConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :video_configs, :music_provider, :string, default: 'jamendo', null: false
  end
end
