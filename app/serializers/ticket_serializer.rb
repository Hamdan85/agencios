# frozen_string_literal: true

# Full ticket detail (the contextual ticket view).
class TicketSerializer < ActiveModel::Serializer
  attributes :id, :title, :display_title, :status, :priority, :position,
             :due_date, :scheduled_at, :published_at, :channels, :creative_type,
             :ai_summaries, :fields, :workflow_step, :next_status,
             :project, :assignee, :created_by, :allowed_field_keys, :created_at,
             :archived, :archived_at, :relations, :connected_channels

  def display_title = object.display_title
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
    "iteration_of" => "Iterado em", "repetition_of" => "Repetido em", "related_to" => "Relacionado a"
  }.freeze

  def relations
    outgoing = object.ticket_relations.includes(:related_ticket).map do |r|
      { ticket_id: r.related_ticket_id, title: r.related_ticket.display_title, label: r.kind_label, kind: r.kind }
    end
    incoming = object.inverse_ticket_relations.includes(:ticket).map do |r|
      { ticket_id: r.ticket_id, title: r.ticket.display_title, label: INCOMING_LABEL.fetch(r.kind, r.kind), kind: r.kind }
    end
    outgoing + incoming
  end

  private

  def person(user)
    return nil unless user

    { id: user.id, name: user.display_name }
  end
end
