# frozen_string_literal: true

# The central unit of agency work, flowing through the content production funnel.
# All status transitions go through Operations::Tickets::ChangeStatus — never a
# bare update! on `status`.
class Ticket < ApplicationRecord
  belongs_to :workspace
  belongs_to :project
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  has_many :subtasks, dependent: :destroy
  has_many :creatives, dependent: :destroy
  has_many :attachments, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :ticket_status_logs, dependent: :destroy

  # `scopes: false` — the `scoping` status would otherwise generate a
  # `Ticket.scoping` scope that clashes with ActiveRecord::Relation#scoping.
  # The board groups by status in a single query; predicates remain available.
  enum :status, {
    ideation: 0, scoping: 1, production: 2, scheduled: 3,
    published: 4, retrospective: 5, done: 6
  }, scopes: false

  enum :priority, { low: 0, medium: 1, high: 2 }, prefix: true

  WORKFLOW = %i[ideation scoping production scheduled published retrospective done].freeze
  CHANNELS = %w[instagram facebook tiktok youtube linkedin x].freeze

  # User-facing PT-BR labels (used in system note copy + frontend label map).
  STATUS_LABELS = {
    "ideation" => "Ideação",
    "scoping" => "Escopo",
    "production" => "Produção",
    "scheduled" => "Agendado",
    "published" => "Postado / Monitorando",
    "retrospective" => "Retrospectiva",
    "done" => "Concluído"
  }.freeze

  validates :status, presence: true

  scope :board_ordered, -> { order(:position, created_at: :desc) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived? = archived_at.present?

  def workflow_step = WORKFLOW.index(status.to_sym)

  def next_status
    idx = workflow_step
    return nil if idx.nil? || idx >= WORKFLOW.length - 1

    WORKFLOW[idx + 1].to_s
  end

  def display_title
    title.presence || [creative_type, project&.name].compact.join(" · ").presence || "Sem título"
  end

  def summary_for(some_status)
    ai_summaries[some_status.to_s]
  end

  # Status-namespaced structured field bag (see Tickets::Fields).
  def fields_for(some_status)
    fields[some_status.to_s] || {}
  end
end
