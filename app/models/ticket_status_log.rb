# frozen_string_literal: true

class TicketStatusLog < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :user, optional: true

  def from_status_key = from_status && Ticket.statuses.key(from_status)
  def to_status_key   = to_status && Ticket.statuses.key(to_status)
end
