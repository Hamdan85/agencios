# frozen_string_literal: true

# Projects gain a fourth lifecycle state, `completed` (enum value 3, added on the
# model). Finalizing a project is the explicit event that generates its end-of-run
# audit report; `archived` stays as plain hide-from-view. `completed_at` stamps the
# moment of finalization (used as the report period's upper bound).
class AddCompletedToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :completed_at, :datetime
  end
end
