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
end
