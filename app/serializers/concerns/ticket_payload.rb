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
end
