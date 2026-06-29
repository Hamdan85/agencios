# frozen_string_literal: true

# Workspace-wide board updates: card_moved, ticket_created, ticket_updated.
class BoardChannel < ApplicationCable::Channel
  def subscribed
    return reject unless member_of?(params[:workspace_id])

    stream_from "board_#{params[:workspace_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
