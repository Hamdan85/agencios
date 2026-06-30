# frozen_string_literal: true

# The "tag" that groups tickets on the board; `color` drives the card chip.
class Project < ApplicationRecord
  belongs_to :workspace
  belongs_to :client
  has_many :tickets, dependent: :destroy
  has_many :invoice_projects, dependent: :destroy
  has_many :invoices, through: :invoice_projects
  has_many :reports, class_name: "ProjectReport", dependent: :destroy

  # `completed` is the explicit "finalized" state that triggers the audit report
  # (see Operations::Projects::Finalize); `archived` stays plain hide-from-view.
  enum :status, { active: 0, paused: 1, archived: 2, completed: 3 }, prefix: true

  validates :name, presence: true

  # The most recent report (the one a finalized project links to).
  def latest_report = reports.order(created_at: :desc).first
end
