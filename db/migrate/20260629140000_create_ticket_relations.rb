# frozen_string_literal: true

# Typed links between tickets. The flagship use: when a `done` ticket recommends
# iterating or repeating, the system spawns a new ideation ticket linked back to
# the source as an "iteration of" / "repetition of".
class CreateTicketRelations < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_relations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: true
      t.references :related_ticket, null: false, foreign_key: { to_table: :tickets }
      t.integer :kind, null: false, default: 0
      t.timestamps
    end

    add_index :ticket_relations, %i[ticket_id related_ticket_id kind], unique: true,
                                                                       name: 'index_ticket_relations_unique'
  end
end
