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
  # detail): nil / pending (awaiting client) / changes_requested. Stage-aware,
  # not the raw creative states: the chip only flags a BLOCKED ticket —
  # "aguardando cliente" while it sits in Aprovação, "ajustes pedidos" while the
  # rework sits in Produção. Later stages show nothing: being in Postagem/No ar
  # already implies the approval resolved (the "Aprovado por" badge in the ticket
  # view carries the provenance). Derived from the preloaded creatives — no
  # extra queries.
  def approval_state
    return nil if object.approval_requested_at.blank?

    if object.production?
      return 'changes_requested' if object.approvable_creatives.any?(&:approval_changes_requested?)
    elsif object.approval?
      return 'pending' unless object.fully_approved?
    end

    nil
  end
end
