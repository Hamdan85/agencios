# frozen_string_literal: true

# Meetings move from workspace-level to user-level: each meeting is owned by the
# user who scheduled it (their own Google Calendar hosts the event). Existing
# meetings are assigned to the workspace owner. The workspace-level Google
# Calendar connection (tokens on Setting) is retired — every user connects
# their own calendar from the account page.
class MoveMeetingsToUserLevel < ActiveRecord::Migration[8.1]
  def up
    add_reference :meetings, :user, foreign_key: true, index: true

    # Backfill: legacy meetings belong to the workspace owner (role 0 = owner).
    execute <<~SQL
      UPDATE meetings
      SET user_id = (
        SELECT memberships.user_id
        FROM memberships
        WHERE memberships.workspace_id = meetings.workspace_id
          AND memberships.role = 0
        LIMIT 1
      )
      WHERE meetings.user_id IS NULL
    SQL

    # Retire the workspace-level calendar connection.
    execute <<~SQL
      UPDATE settings
      SET google_access_token = NULL,
          google_refresh_token = NULL,
          google_calendar_connected_at = NULL
      WHERE google_access_token IS NOT NULL
         OR google_refresh_token IS NOT NULL
         OR google_calendar_connected_at IS NOT NULL
    SQL
  end

  def down
    remove_reference :meetings, :user
  end
end
