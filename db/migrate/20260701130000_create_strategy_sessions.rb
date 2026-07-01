# frozen_string_literal: true

# The AI content-strategy planning conversation for a project. A social-media
# senior agent chats with the user (transcript in `messages`), covering gaps
# until the monthly cadence is feasible, then proposes a structured content plan
# (`proposed_plan`) that, once approved, is fanned out into scheduled tickets +
# back-scheduled subtasks. One active session per project at a time.
class CreateStrategySessions < ActiveRecord::Migration[8.1]
  def change
    create_table :strategy_sessions do |t|
      t.references :workspace, null: false, foreign_key: true, index: false
      t.references :project, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.string :status, null: false, default: 'active' # active | proposed | applied | discarded
      t.jsonb  :messages, null: false, default: []      # [{ role, content, ts }]
      t.jsonb  :proposed_plan, null: false, default: {} # latest structured plan from the tool call

      t.timestamps
    end

    add_index :strategy_sessions, %i[workspace_id created_at]
    add_index :strategy_sessions, %i[project_id status]
  end
end
