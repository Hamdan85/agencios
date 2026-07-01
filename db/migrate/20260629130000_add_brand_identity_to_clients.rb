# frozen_string_literal: true

# Brand identity belongs to the CLIENT, not only the agency (workspace). Each
# client carries its own voice, @handle, brand colors, logo and creator avatar
# (logo + avatar are ActiveStorage attachments). The workspace brand stays as the
# agency-level default/fallback. `brand_voice` moves out of the positioning bag
# into a first-class column.
class AddBrandIdentityToClients < ActiveRecord::Migration[8.1]
  def up
    add_column :clients, :brand_voice, :text
    add_column :clients, :default_handle, :string
    add_column :clients, :brand_primary_color, :string, default: '#7C3AED', null: false
    add_column :clients, :brand_secondary_color, :string, default: '#F59E0B', null: false

    # Lift any brand_voice that was captured inside the positioning jsonb.
    execute <<~SQL.squish
      UPDATE clients
      SET brand_voice = positioning->>'brand_voice'
      WHERE positioning ? 'brand_voice' AND (positioning->>'brand_voice') <> ''
    SQL
    execute "UPDATE clients SET positioning = positioning - 'brand_voice'"
  end

  def down
    remove_column :clients, :brand_voice
    remove_column :clients, :default_handle
    remove_column :clients, :brand_primary_color
    remove_column :clients, :brand_secondary_color
  end
end
