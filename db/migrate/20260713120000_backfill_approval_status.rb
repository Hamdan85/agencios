# frozen_string_literal: true

# `approval` became a real funnel status (Ticket::WORKFLOW), where before it was a
# shadow state: a ticket in `production` with `approval_requested_at` set and a
# ready creative still pending the client's decision. Move those rows into the new
# status so they land in the Aprovação column instead of hiding in Produção.
#
# Deliberately raw SQL, not ChangeStatus: this is a backfill of what the rows
# already meant, not a transition — it must not log, note, notify or broadcast.
class BackfillApprovalStatus < ActiveRecord::Migration[8.1]
  PRODUCTION = 2
  APPROVAL = 7
  CREATIVE_READY = 2

  def up
    execute(<<~SQL.squish)
      UPDATE tickets SET status = #{APPROVAL}
      WHERE status = #{PRODUCTION}
        AND approval_requested_at IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM creatives c
          WHERE c.ticket_id = tickets.id
            AND c.approval_state = 'pending'
            AND c.status = #{CREATIVE_READY}
            AND c.id NOT IN (SELECT parent_id FROM creatives WHERE parent_id IS NOT NULL)
        )
    SQL
  end

  def down
    execute("UPDATE tickets SET status = #{PRODUCTION} WHERE status = #{APPROVAL}")
  end
end
