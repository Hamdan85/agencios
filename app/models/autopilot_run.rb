# frozen_string_literal: true

# A single "GO mode" run. Autopilot walks an eligible ticket from its current
# stage through to `scheduled` on its own: fills every briefing field, generates
# all of its creatives (carousel/image/video) and schedules the posts.
#
# This is a PURE state record — every transition goes through an
# `Operations::Autopilot::*` operation (mirroring the "ChangeStatus is the only
# transition point" convention). No side-effect callbacks live here.
#
# `scope`:
#   * `ticket` — a worker run bound to one ticket (the unit that walks itself).
#   * `batch`  — a project/strategy coordinator with no ticket; its child
#                ticket-runs point at it via `batch_id` and it aggregates them.
class AutopilotRun < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket, optional: true
  belongs_to :user, optional: true
  belongs_to :batch, class_name: 'AutopilotRun', optional: true
  has_many :children, class_name: 'AutopilotRun', foreign_key: :batch_id,
                      dependent: :nullify, inverse_of: :batch

  SCOPES = %w[ticket batch].freeze

  # Ticket-run lifecycle.
  ACTIVE_STATES   = %w[pending scoping generating awaiting_generation publishing].freeze
  TERMINAL_STATES = %w[completed failed cancelled].freeze
  STATES          = (ACTIVE_STATES + TERMINAL_STATES).freeze

  # Batch-coordinator lifecycle.
  BATCH_ACTIVE_STATES   = %w[pending running].freeze
  BATCH_TERMINAL_STATES = %w[completed completed_with_failures failed cancelled].freeze

  MODES = %w[immediate scheduled].freeze

  validates :scope, inclusion: { in: SCOPES }

  scope :ticket_runs, -> { where(scope: 'ticket') }
  scope :batches,     -> { where(scope: 'batch') }
  scope :active,      -> { where(state: ACTIVE_STATES) }

  def ticket_scope? = scope == 'ticket'
  def batch_scope?  = scope == 'batch'

  def active?   = (batch_scope? ? BATCH_ACTIVE_STATES : ACTIVE_STATES).include?(state)
  def terminal? = (batch_scope? ? BATCH_TERMINAL_STATES : TERMINAL_STATES).include?(state)

  def generation_ids = Array(progress['generation_ids']).map(&:to_i)
  def creative_ids    = Array(progress['creative_ids']).map(&:to_s)
end
