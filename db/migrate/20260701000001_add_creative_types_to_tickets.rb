# frozen_string_literal: true

# A ticket now scopes MANY creative types (multi-select, like channels), not one.
# `creative_types` is the array source; the legacy `creative_type` column is kept
# in sync with the first entry so board chips / filters keep working.
class AddCreativeTypesToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :creative_types, :string, array: true, null: false, default: []

    say_with_time 'Backfilling tickets.creative_types from the legacy creative_type' do
      execute(<<~SQL.squish)
        UPDATE tickets
        SET creative_types = ARRAY[creative_type]
        WHERE creative_type IS NOT NULL AND creative_type <> ''
      SQL
    end

    say_with_time 'Migrating fields.scoping.creative_type and fields.scheduled.creative_id' do
      Ticket.reset_column_information
      Ticket.find_each do |ticket|
        fields = ticket.fields || {}
        changed = false

        scoping = fields['scoping']
        if scoping.is_a?(Hash) && scoping['creative_type'].present? && scoping['creative_types'].blank?
          scoping['creative_types'] = [scoping['creative_type']]
          changed = true
        end

        scheduled = fields['scheduled']
        if scheduled.is_a?(Hash) && scheduled['creative_id'].present? && scheduled['creative_ids'].blank?
          scheduled['creative_ids'] = [scheduled['creative_id']]
          changed = true
        end

        ticket.update_column(:fields, fields) if changed
      end
    end
  end

  def down
    remove_column :tickets, :creative_types
  end
end
