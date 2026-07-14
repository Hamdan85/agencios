# frozen_string_literal: true

# Compact card for the Kanban board.
class TicketCardSerializer < ActiveModel::Serializer
  include TicketPayload

  attributes :id, :title, :display_title, :status, :priority, :position,
             :due_date, :scheduled_at, :channels, :creative_type,
             :project, :assignee, :subtasks_count, :subtasks_done, :creatives_count,
             :overdue, :autopilot_running, :in_alert, :alert_reason, :approval

  # True while the ticket is walking itself in GO mode — drives the card/row
  # "working" indicator.
  def autopilot_running = object.autopilot_running?

  # Lean approval summary for the card/row chip ("Aguardando cliente" etc.) —
  # the full detail serializer layers fully_approved + actor name on top.
  def approval
    { state: approval_state, requested_at: object.approval_requested_at&.iso8601 }
  end

  def project
    p = object.project
    return nil unless p

    { id: p.id, name: p.name, color: p.color }
  end

  def assignee
    a = object.assignee
    return nil unless a

    { id: a.id, name: a.display_name, avatar_url: avatar_url(a) }
  end

  def subtasks_count = object.subtasks.size
  def subtasks_done  = object.subtasks.count(&:done)
  def creatives_count = object.creatives.size

  private

  def avatar_url(user)
    return nil unless user.avatar.attached?

    Rails.application.routes.url_helpers.rails_blob_url(user.avatar, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end
end
