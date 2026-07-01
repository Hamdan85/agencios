# frozen_string_literal: true

# An autopilot ("GO mode") run — the walk state + progress the ticket/board UI
# renders as a run chip.
class AutopilotRunSerializer < ActiveModel::Serializer
  attributes :id, :scope, :state, :mode, :target_status,
             :ticket_id, :batch_id, :estimated_credits, :spent_credits,
             :scheduled_at, :progress, :failure_reason,
             :active, :terminal, :started_at, :finished_at

  def active = object.active?
  def terminal = object.terminal?
  def scheduled_at = object.scheduled_at&.iso8601
  def started_at = object.started_at&.iso8601
  def finished_at = object.finished_at&.iso8601
end
