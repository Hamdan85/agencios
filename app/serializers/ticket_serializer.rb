# frozen_string_literal: true

# Full ticket detail (the contextual ticket view).
class TicketSerializer < ActiveModel::Serializer
  attributes :id, :title, :display_title, :status, :priority, :position,
             :due_date, :scheduled_at, :published_at, :channels, :creative_type, :creative_types,
             :ai_summaries, :fields, :workflow_step, :next_status,
             :project, :assignee, :created_by, :allowed_field_keys, :created_at,
             :archived, :archived_at, :relations, :connected_channels, :overdue,
             :autopilot_eligible, :autopilot_run, :in_alert, :alert_reason, :approval

  def display_title = object.display_title
  def overdue = object.overdue?
  def in_alert = object.in_alert?
  def due_date = object.due_date&.iso8601
  def scheduled_at = object.scheduled_at&.iso8601
  def published_at = object.published_at&.iso8601
  def created_at = object.created_at.iso8601
  def archived = object.archived?
  def archived_at = object.archived_at&.iso8601
  def workflow_step = object.workflow_step
  def next_status = object.next_status
  def allowed_field_keys = Tickets::Fields.allowed_keys(object.status)

  def project
    p = object.project
    return nil unless p

    { id: p.id, name: p.name, color: p.color, client_id: p.client&.id, client_name: p.client&.name }
  end

  def assignee = person(object.assignee)
  def created_by = person(object.created_by)

  # Which networks the ticket's client has actually connected — drives the
  # "disabled channel → connect" affordance in the contextual ticket view.
  def connected_channels
    client = object.project&.client
    client ? client.social_accounts.pluck(:provider) : []
  end

  # Typed links to other tickets, both directions, flattened for the UI.
  INCOMING_LABEL = {
    'iteration_of' => 'Iterado em', 'repetition_of' => 'Repetido em', 'related_to' => 'Relacionado a'
  }.freeze

  def relations
    outgoing = object.ticket_relations.includes(:related_ticket).map do |r|
      { ticket_id: r.related_ticket_id, title: r.related_ticket.display_title, label: r.kind_label, kind: r.kind }
    end
    incoming = object.inverse_ticket_relations.includes(:ticket).map do |r|
      { ticket_id: r.ticket_id, title: r.ticket.display_title, label: INCOMING_LABEL.fetch(r.kind, r.kind),
        kind: r.kind }
    end
    outgoing + incoming
  end

  # Whether the ticket can run on autopilot (every scoped creative type is
  # auto-generatable) — the GO button is only offered when true.
  def autopilot_eligible
    Operations::Autopilot::Eligibility.call(ticket: object)[:eligible]
  end

  # The in-flight GO run, if any (drives the run chip + disables the button).
  def autopilot_run
    run = object.active_autopilot_run
    run && AutopilotRunSerializer.new(run).as_json
  end

  # Approval summary for the production/publication view (drives ApprovalPanel) and
  # the ticket-row chip. `state`: nil (not in the flow) / pending (awaiting client)
  # / approved / changes_requested.
  def approval
    {
      requested_at: object.approval_requested_at&.iso8601,
      fully_approved: object.fully_approved?,
      state: approval_state,
      actor_name: object.approval_actor&.then { |a| a.respond_to?(:name) ? a.name : nil }
    }
  end

  def approval_state
    return nil if object.approval_requested_at.blank?
    return 'approved' if object.fully_approved?

    creatives = object.approvable_creatives
    return 'changes_requested' if creatives.any?(&:approval_changes_requested?) && creatives.none?(&:approval_pending?)

    'pending'
  end

  private

  def person(user)
    return nil unless user

    { id: user.id, name: user.display_name }
  end
end
