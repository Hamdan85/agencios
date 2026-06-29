# frozen_string_literal: true

# Per-ticket live updates: status_changed, summary_ready, creative_ready,
# post_published, metric_updated, note_added.
class TicketChannel < ApplicationCable::Channel
  def subscribed
    ticket = Ticket.where(workspace_id: current_user.workspaces.select(:id)).find_by(id: params[:ticket_id])
    return reject unless ticket

    stream_from "ticket_#{ticket.id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
