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
  # detail): nil / pending (awaiting client) / approved / changes_requested.
  # Stage-aware, not just the raw creative states: "aguardando cliente" is only
  # true while the ticket IS in Aprovação, and "ajustes pedidos" only while the
  # work is back in Produção. A ticket that moved past approval without a full
  # sign-off (manual drag, pre-flow data) shows nothing — that moment has passed.
  # "Aprovado" persists anywhere as provenance. Derived from the preloaded
  # creatives — no extra queries.
  def approval_state
    return nil if object.approval_requested_at.blank?
    return 'approved' if object.fully_approved?

    if object.production?
      creatives = object.approvable_creatives
      return 'changes_requested' if creatives.any?(&:approval_changes_requested?)
    end

    object.approval? ? 'pending' : nil
  end
end
