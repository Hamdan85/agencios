# frozen_string_literal: true

# A comment can @-mention workspace members. The resolved (validated) user ids
# are stored here as the authoritative list driving mention emails — the body
# carries `@[Name](id)` tokens only for rendering.
class AddMentionedUserIdsToNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :notes, :mentioned_user_ids, :jsonb, null: false, default: []
  end
end
