# frozen_string_literal: true

# The "tag" that groups tickets on the board; `color` drives the card chip.
class Project < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :tickets, dependent: :destroy
  has_many :invoice_projects, dependent: :destroy
  has_many :invoices, through: :invoice_projects
  has_many :reports, class_name: 'ProjectReport', dependent: :destroy
  has_many :strategy_sessions, dependent: :destroy

  # Lifecycle: a project is born `draft` (planning), is explicitly started into
  # `active` (Operations::Projects::Start), and ends `completed` — the finalized
  # state that triggers the audit report (Operations::Projects::Finalize).
  # `paused` / `archived` are plain side states.
  enum :status, { active: 0, paused: 1, archived: 2, completed: 3, draft: 4 }, prefix: true

  validates :name, presence: true

  # The most recent report (the one a finalized project links to).
  def latest_report = reports.order(created_at: :desc).first

  # Approval/publishing/scheduling config: defaults + workspace fallback merged
  # with the project's own stored `settings` (see Tickets::ProjectSettings).
  def resolved_settings
    Tickets::ProjectSettings.resolve(self)
  end

  def setting(key)
    resolved_settings[key.to_s]
  end

  # The in-flight project-level "GO mode" batch, if any. A batch coordinator has
  # no project of its own — it's linked only through the ticket-runs it spawned,
  # so we resolve it from this project's tickets. At most one is active in
  # practice; a terminal batch (completed / failed / cancelled) resolves to nil,
  # so the project GO button reappears once the run stops.
  def active_autopilot_batch
    batch_ids = AutopilotRun.ticket_runs
                            .where(ticket_id: tickets.select(:id))
                            .where.not(batch_id: nil)
                            .distinct.pluck(:batch_id)
    return nil if batch_ids.empty?

    AutopilotRun.batches
                .where(id: batch_ids, state: AutopilotRun::BATCH_ACTIVE_STATES)
                .order(started_at: :desc)
                .first
  end

  # Did this campaign ever run in GO (autopilot) mode? True when any autopilot
  # ticket-run exists over the project's tickets (active or terminal). Drives the
  # auto-send of the finalized report to the client (Operations::Reports::SendToClient).
  def go_mode?
    AutopilotRun.ticket_runs.where(ticket_id: tickets.select(:id)).exists?
  end
end
