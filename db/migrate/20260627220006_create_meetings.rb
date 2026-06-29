# frozen_string_literal: true

class CreateMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :meetings do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :client, foreign_key: true
      t.references :project, foreign_key: true
      t.string   :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string   :google_event_id
      t.string   :meet_url
      t.jsonb    :attendees, null: false, default: []
      t.text     :notes
      t.timestamps
    end
    add_index :meetings, %i[workspace_id starts_at]
  end
end
