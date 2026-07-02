# frozen_string_literal: true

# Compact card for the Kanban board.
class TicketCardSerializer < ActiveModel::Serializer
  attributes :id, :title, :display_title, :status, :priority, :position,
             :due_date, :scheduled_at, :channels, :creative_type,
             :project, :assignee, :subtasks_count, :subtasks_done, :creatives_count,
             :overdue, :autopilot_running

  def display_title = object.display_title
  def due_date = object.due_date&.iso8601
  def scheduled_at = object.scheduled_at&.iso8601
  def overdue = object.overdue?
  # True while the ticket is walking itself in GO mode — drives the card/row
  # "working" indicator.
  def autopilot_running = object.autopilot_running?

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
