# frozen_string_literal: true

# The central unit of agency work, flowing through the content production funnel.
# All status transitions go through Operations::Tickets::ChangeStatus — never a
# bare update! on `status`.
class Ticket < ApplicationRecord
  belongs_to :workspace
  belongs_to :project
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  # The strategy-planner session that created this ticket, when it came from an
  # applied content plan (nil for hand-made tickets). Lets a re-apply of an
  # edited plan rewrite its batch from scratch.
  belongs_to :strategy_session, optional: true

  has_many :subtasks, dependent: :destroy
  has_many :creatives, dependent: :destroy
  has_many :attachments, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :ticket_status_logs, dependent: :destroy
  has_many :autopilot_runs, dependent: :destroy

  # Typed links to other tickets. `ticket_relations` are this ticket's OUTGOING
  # links (e.g. "this is an iteration of #4"); `inverse_ticket_relations` are
  # INCOMING (e.g. "#9 is an iteration of this").
  has_many :ticket_relations, dependent: :destroy
  has_many :related_tickets, through: :ticket_relations
  has_many :inverse_ticket_relations, class_name: 'TicketRelation',
                                      foreign_key: :related_ticket_id, dependent: :destroy

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

  # Image creative types that ride a video post as its cover/thumbnail rather than
  # posting standalone (see Operations::Tickets::Publish). Mirrored on the frontend.
  COVER_TYPES = %w[thumbnail cover].freeze

  # User-facing PT-BR labels (used in system note copy + frontend label map).
  STATUS_LABELS = {
    'ideation' => 'Ideação',
    'scoping' => 'Escopo',
    'production' => 'Produção',
    'scheduled' => 'Postagem',
    'published' => 'No ar',
    'retrospective' => 'Retrospectiva',
    'done' => 'Concluído'
  }.freeze

  validates :status, presence: true

  scope :board_ordered, -> { order(:position, created_at: :desc) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # Tickets under a still-live campaign. Operational surfaces (board, ticket
  # list, calendar, My Tasks, dashboard counts) use this to drop work belonging
  # to an archived project — which is how an archived CLIENT's tickets fall out,
  # since archiving a client cascade-archives its projects. History stays
  # reachable through the client/project pages. Subquery (not a join) so it
  # composes with any existing scope/includes without double-joining.
  scope :in_live_project, -> { where(project_id: Project.where.not(status: :archived)) }

  # Due today or earlier — falls back to `scheduled_at`'s date when no
  # `due_date` is set. Feeds the daily ticket digest (Operations::Digests).
  scope :due_or_overdue, lambda {
    where(
      '(due_date IS NOT NULL AND due_date <= :today) OR ' \
      '(due_date IS NULL AND scheduled_at IS NOT NULL AND scheduled_at::date <= :today)',
      today: Date.current
    )
  }

  def archived? = archived_at.present?

  def workflow_step = WORKFLOW.index(status.to_sym)

  # Derived "atrasado" state (never a workflow status): the post's expected date
  # has passed and the ticket has not reached `published` yet. Computed at read
  # time and serialized as `overdue` — the board/ticket header render the badge.
  def overdue?
    return false if scheduled_at.blank? || archived?

    scheduled_at.past? && (workflow_step.nil? || workflow_step < WORKFLOW.index(:published))
  end

  def next_status
    idx = workflow_step
    return nil if idx.nil? || idx >= WORKFLOW.length - 1

    WORKFLOW[idx + 1].to_s
  end

  def display_title
    title.presence || [creative_type, project&.name].compact.join(' · ').presence || 'Sem título'
  end

  def summary_for(some_status)
    ai_summaries[some_status.to_s]
  end

  # The in-flight "GO mode" run, if any (the ticket is walking itself). At most
  # one active run exists at a time (enforced by a unique partial index).
  def active_autopilot_run
    autopilot_runs.ticket_runs.active.order(created_at: :desc).first
  end

  # Is this ticket executing on autopilot right now? Reads the loaded association
  # in Ruby (preload `:autopilot_runs`) so the board/list can flag "working" cards
  # without an N+1. Surfaced to cards/rows via TicketCardSerializer.
  def autopilot_running?
    autopilot_runs.any? { |r| r.ticket_scope? && r.active? }
  end

  # A ticket in "alert" needs human attention — something broke at posting time
  # (a failed publish). `alert_reason` holds the why; cleared on a clean publish.
  def in_alert?
    alert_reason.present?
  end

  # Status-namespaced structured field bag (see Tickets::Fields).
  def fields_for(some_status)
    fields[some_status.to_s] || {}
  end

  # The creative types scoped for this ticket. Source of truth is the scoping
  # field bag; the top-level column mirrors it (and the legacy single column) so
  # board chips / filters keep working.
  def creative_types_list
    list = Array(fields_for('scoping')['creative_types']).map(&:to_s).compact_blank
    list = Array(creative_types).map(&:to_s).compact_blank if list.blank?
    list = Array(creative_type).map(&:to_s).compact_blank if list.blank?
    # De-dup at the read choke point so a duplicate type (the GO "two identical
    # creatives" bug) never produces duplicate generations — fixes legacy data too.
    list.uniq
  end

  # A ticket's random, revocable approval-link secret. Lazily minted; stable
  # across calls so "reenviar link" reuses the same URL. Powers /aprovar/:token.
  def approval_token!
    return approval_token if approval_token.present?

    update!(approval_token: "apv_#{SecureRandom.urlsafe_base64(32)}")
    approval_token
  end

  # Coarse SQL filter for the client-approval queue: approval was requested and
  # the ticket has at least one ready creative still pending a decision. Refined
  # by #pending_client_approval? (which also excludes superseded creatives).
  scope :awaiting_client_approval, lambda {
    where.not(approval_requested_at: nil)
         .where(id: Creative.where(approval_state: 'pending', status: Creative.statuses[:ready]).select(:ticket_id))
  }

  # In the client portal iff approval was requested and there is still an
  # approvable creative awaiting the client's decision.
  def pending_client_approval?
    approval_requested_at.present? && approvable_creatives.any?(&:approval_pending?)
  end

  # The creatives the client approves: ready, not superseded by a newer version
  # (a creative referenced as another creative's parent), and not a discarded
  # option (`not_selected`, i.e. a loser among several in a slot).
  def approvable_creatives
    ready = creatives.select(&:status_ready?)
    superseded_ids = creatives.filter_map(&:parent_id).to_set
    ready.reject { |c| superseded_ids.include?(c.id) || c.approval_not_selected? }
  end

  # Approvable creatives grouped into media-type SLOTS (one slot per creative_type),
  # ordered by the ticket's creative_types_list. The client decides per slot.
  def approval_slots
    by_type = approvable_creatives.group_by(&:creative_type)
    ordered = (creative_types_list & by_type.keys) + (by_type.keys - creative_types_list)
    ordered.index_with { |type| by_type[type] }
  end

  # The chosen winner of each slot (≤1 per slot after selection).
  def approved_winners = approvable_creatives.select(&:approval_approved?)

  # Fully approved iff every slot has an approved winner.
  def fully_approved?
    slots = approval_slots
    slots.any? && slots.values.all? { |options| options.any?(&:approval_approved?) }
  end

  # The team member accountable for this ticket — notified of client decisions.
  # Assignee first, then whoever last ran it on autopilot, then its creator, then
  # the workspace owner as a final fallback.
  def responsible_user
    assignee ||
      autopilot_runs.order(created_at: :desc).first&.user ||
      created_by ||
      workspace.owner
  end

  # The reviewer (User or Client) of the most recently decided approved creative
  # — drives "Aprovado por <actor>".
  def approval_actor
    approvable_creatives.select(&:approval_approved?)
                        .max_by { |c| c.decided_at || Time.at(0) }&.reviewed_by
  end
end
