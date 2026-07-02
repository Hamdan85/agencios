# frozen_string_literal: true

# A ticket enters an "alert" state when something breaks at posting time (a
# failed publish: missing creative, a disconnected network, an API error). The
# reason is stored here (nil = no alert) and a task is generated for the team to
# address it. Cleared once the ticket publishes successfully.
class AddAlertReasonToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :alert_reason, :string
  end
end
