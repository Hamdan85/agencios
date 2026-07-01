# frozen_string_literal: true

# A typed link from `ticket` to `related_ticket`. Read as "<ticket> is a <kind>
# <related_ticket>" — e.g. ticket #9 `iteration_of` ticket #4.
class TicketRelation < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :related_ticket, class_name: 'Ticket'

  enum :kind, { iteration_of: 0, repetition_of: 1, related_to: 2 }, prefix: true

  # User-facing PT-BR labels for each relation kind.
  KIND_LABELS = {
    'iteration_of' => 'Iteração de',
    'repetition_of' => 'Repetição de',
    'related_to' => 'Relacionado a'
  }.freeze

  def kind_label = KIND_LABELS.fetch(kind, kind)
end
