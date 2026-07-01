# frozen_string_literal: true

# The AI content-strategy planning conversation for a project. The agent (a
# social-media senior) chats with the user until the monthly cadence is feasible,
# then proposes a structured `proposed_plan` (via a tool call) that
# Operations::Strategy::Apply fans out into scheduled tickets + subtasks.
class StrategySession < ApplicationRecord
  belongs_to :workspace
  belongs_to :project
  belongs_to :user, optional: true

  # Tickets created by applying this session's plan. Re-applying an edited plan
  # rewrites this set from scratch; the link is nullified (not destroyed) if the
  # session itself is ever deleted.
  has_many :tickets, dependent: :nullify

  # Stored as a string column (active | proposed | applied | discarded); keep the
  # enum backed by strings so the DB stays human-readable.
  enum :status, {
    active: 'active', proposed: 'proposed', applied: 'applied', discarded: 'discarded'
  }, prefix: true, default: 'active'

  scope :recent, -> { order(created_at: :desc) }

  # Append a chat turn to the transcript. `ts` is an ISO timestamp so the
  # frontend can render ordering without a separate messages table.
  def push_message(role:, content:)
    self.messages = Array(messages) + [{ 'role' => role.to_s, 'content' => content.to_s, 'ts' => Time.current.iso8601 }]
  end

  def proposed_plan?
    proposed_plan.present? && Array(proposed_plan['tickets']).any?
  end
end
