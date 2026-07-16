# frozen_string_literal: true

# Uploaded creatives were left in `draft` (the column default) forever — nothing
# ever promoted them, so they never showed up in Aprovação/Postagem (both require
# `ready`). Uploads are now created `ready`; this promotes the existing ones that
# actually carry a file. Data-only, one-way.
class PromoteUploadedDraftCreativesToReady < ActiveRecord::Migration[8.1]
  def up
    # source 0 = uploaded, status 0 = draft, 2 = ready (Creative enums).
    execute <<~SQL.squish
      UPDATE creatives SET status = 2, updated_at = NOW()
      WHERE source = 0 AND status = 0
        AND id IN (
          SELECT record_id FROM active_storage_attachments
          WHERE record_type = 'Creative' AND name = 'assets'
        )
    SQL
  end

  def down
    # Data fix — nothing sensible to restore.
  end
end
