# frozen_string_literal: true

# The end-of-run audit report for a project — the multi-section deck generated
# when a project is finalized. `data` holds the full report document (computed KPI
# block + the structured AI sections: wins, bottlenecks, opportunities, matrix,
# overall grade, action plan, projection, growth angle). `overall_score` is
# denormalized out of `data` for cheap list rendering.
class CreateProjectReports < ActiveRecord::Migration[8.1]
  def change
    create_table :project_reports do |t|
      t.references :project, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true, index: false

      t.integer  :status, null: false, default: 0 # generating | ready | failed
      t.date     :period_start
      t.date     :period_end
      t.decimal  :overall_score, precision: 4, scale: 2
      t.jsonb    :data, null: false, default: {}
      t.datetime :generated_at

      t.timestamps
    end

    add_index :project_reports, %i[project_id created_at]
    add_index :project_reports, %i[workspace_id created_at]
  end
end
