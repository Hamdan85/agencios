# frozen_string_literal: true

class CreateTicketsDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :created_by, foreign_key: { to_table: :users }
      t.string   :title
      t.integer  :status, null: false, default: 0
      t.integer  :priority, null: false, default: 1
      t.integer  :position, null: false, default: 0
      t.date     :due_date
      t.datetime :scheduled_at
      t.string   :channels, array: true, null: false, default: []
      t.string   :creative_type
      t.jsonb    :ai_summaries, null: false, default: {}
      t.jsonb    :fields, null: false, default: {}
      t.datetime :published_at
      t.datetime :archived_at
      t.timestamps
    end
    add_index :tickets, %i[workspace_id status position]
    add_index :tickets, %i[workspace_id scheduled_at]

    create_table :ticket_status_logs do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer    :from_status
      t.integer    :to_status, null: false
      t.timestamps
    end

    create_table :notes do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text    :body
      t.integer :kind, null: false, default: 0
      t.timestamps
    end
    add_index :notes, %i[ticket_id created_at]

    create_table :subtasks do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string  :title, null: false
      t.boolean :done, null: false, default: false
      t.date    :due_date
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :subtasks, %i[assignee_id done]
  end
end
