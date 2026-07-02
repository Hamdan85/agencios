# frozen_string_literal: true

# The production-stage free-text field is really the production scope that guides
# creative generation, not "internal notes". Rename the jsonb key in every
# ticket's production field bag (fields.production.internal_notes → production_scope)
# so existing data carries over.
class RenameInternalNotesToProductionScope < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE tickets
      SET fields = jsonb_set(
            fields #- '{production,internal_notes}',
            '{production,production_scope}',
            fields->'production'->'internal_notes'
          )
      WHERE fields -> 'production' ? 'internal_notes'
    SQL
  end

  def down
    execute(<<~SQL.squish)
      UPDATE tickets
      SET fields = jsonb_set(
            fields #- '{production,production_scope}',
            '{production,internal_notes}',
            fields->'production'->'production_scope'
          )
      WHERE fields -> 'production' ? 'production_scope'
    SQL
  end
end
