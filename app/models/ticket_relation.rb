# frozen_string_literal: true

# A typed link from `ticket` to `related_ticket`. Read as "<ticket> is a <kind>
# <related_ticket>" — e.g. ticket #9 `iteration_of` ticket #4.
class TicketRelation < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :related_ticket, class_name: 'Ticket'

  enum :kind, { iteration_of: 0, repetition_of: 1, related_to: 2 }, prefix: true

  def kind_label = I18n.t("models.ticket_relation.#{kind}", default: kind.to_s)
end
