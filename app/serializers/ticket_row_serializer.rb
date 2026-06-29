# frozen_string_literal: true

# A row in the global ticket list. Extends the board card with the client name,
# archive state and timestamps the table surfaces.
class TicketRowSerializer < TicketCardSerializer
  attributes :archived, :archived_at, :created_at, :updated_at, :client

  def archived = object.archived?
  def archived_at = object.archived_at&.iso8601
  def created_at = object.created_at&.iso8601
  def updated_at = object.updated_at&.iso8601

  def client
    c = object.project&.client
    return nil unless c

    { id: c.id, name: c.name }
  end
end
