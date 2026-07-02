# frozen_string_literal: true

# The AI content-strategy planning conversation for a project — ONE per project,
# forever (unique index on project_id). The agent (a social-media senior) chats
# with the user, proposes structured `proposed_plan`s (via tool calls) that
# Operations::Strategy::Apply fans out into scheduled tickets + subtasks, and the
# conversation just continues: applying or discarding a plan returns the session
# to `active`, never retires it, so the strategist keeps the project's full memory.
class StrategySession < ApplicationRecord
  belongs_to :workspace
  belongs_to :project
  belongs_to :user, optional: true

  # Tickets created by applying this session's plans. The link is nullified (not
  # destroyed) if the session itself is ever deleted.
  has_many :tickets, dependent: :nullify

  # Stored as a string column; `active` (conversing) and `proposed` (a plan
  # awaiting a decision) are the living states. `applied` / `discarded` are
  # LEGACY-only — kept in the enum so historical rows stay readable, but no
  # transition writes them anymore (the session is eternal).
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
