# frozen_string_literal: true

# Generic file attachments on a ticket. Distinct from Creatives (which are
# produced deliverables bound to a `creative_type` spec + the generation /
# metering pipeline): an Attachment is any file an agency uploads to a ticket —
# briefs, references, raw footage, PDFs, contracts, brand assets, etc. — and is
# available across every workflow status. One ActiveStorage file per row.
class CreateAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :attachments do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.string  :title
      t.text    :description
      t.integer :position, null: false, default: 0
      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :attachments, %i[ticket_id position]
    add_index :attachments, %i[workspace_id created_at]
  end
end
