# frozen_string_literal: true

# Thin, never-raising facade over Action Cable broadcasts. Operations call this
# to push real-time events; a broadcast failure must never break the operation.
module Broadcaster
  module_function

  def ticket(ticket, event, payload = {})
    broadcast("ticket_#{ticket.id}", event, payload)
  end

  def board(workspace_id, event, payload = {})
    broadcast("board_#{workspace_id}", event, payload)
  end

  def generations(workspace_id, event, payload = {})
    broadcast("generations_#{workspace_id}", event, payload)
  end

  def broadcast(stream, event, payload)
    ActionCable.server.broadcast(stream, { event: event }.merge(payload))
  rescue StandardError => e
    Rails.logger.warn("[Broadcaster] #{stream} #{event} failed: #{e.message}")
  end
end
