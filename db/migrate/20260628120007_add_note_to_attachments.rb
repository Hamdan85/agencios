# frozen_string_literal: true

# Files attached inside a ticket comment reuse the Attachment model (so they
# also appear in the ticket file list) but additionally reference the comment.
# Nullable + nullify: deleting the comment leaves its files in the file list.
class AddNoteToAttachments < ActiveRecord::Migration[8.1]
  def change
    add_reference :attachments, :note, null: true, foreign_key: { on_delete: :nullify }, index: true
  end
end
