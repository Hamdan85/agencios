# frozen_string_literal: true

# Field readers shared verbatim by the Ticket serializer family
# (TicketSerializer, TicketCardSerializer — and TicketRowSerializer through
# inheritance). Shapes that differ per surface (project, assignee) stay in the
# individual serializers.
module TicketPayload
  def display_title = object.display_title
  def due_date = object.due_date&.iso8601
  def scheduled_at = object.scheduled_at&.iso8601
  def overdue = object.overdue?
  def in_alert = object.in_alert?

  # Client-approval chip state, shared by every ticket surface (card, row, full
  # detail): nil / changes_requested. The chip exists ONLY to flag a ticket
  # blocked on client feedback — back in Produção with requested changes.
  # Everything else is already said elsewhere: the Aprovação column means
  # "awaiting the approver", and a later column implies the approval resolved
  # (the "Aprovado por" badge in the ticket view carries the provenance).
  # Derived from the preloaded creatives — no extra queries.
  def approval_state
    return nil if object.approval_requested_at.blank?
    return nil unless object.production?

    object.approvable_creatives.any?(&:approval_changes_requested?) ? 'changes_requested' : nil
  end
end
