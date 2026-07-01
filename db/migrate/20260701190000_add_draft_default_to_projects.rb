# frozen_string_literal: true

# Projects now begin life as `draft` (status: 4) — the strategist plans and
# starts them explicitly (draft → active → completed). Existing rows keep their
# current status; only the default for new rows changes.
class AddDraftDefaultToProjects < ActiveRecord::Migration[8.1]
  def up
    change_column_default :projects, :status, from: 0, to: 4
  end

  def down
    change_column_default :projects, :status, from: 4, to: 0
  end
end
