# frozen_string_literal: true

module Controllers
  module Public
    module Portal
      # A read-only, client-safe Kanban of one campaign: the WORKFLOW columns with
      # each ticket's scope + progress. No internal assignees, briefs-as-notes, or
      # drag affordances — the client follows the work, they don't edit it.
      class Board < Base
        def call
          project = project!
          grouped = project.tickets
                           .includes(:subtasks, creatives: { assets_attachments: :blob })
                           .order(:position, :created_at)
                           .group_by(&:status)
          {
            campaign: { id: project.id, name: project.name, color: project.color,
                        status: project.status, status_label: Controllers::Public::Portal.status_label(project.status) },
            columns: Ticket::WORKFLOW.map do |status|
              tickets = grouped[status.to_s] || []
              {
                status: status.to_s,
                label: Ticket::STATUS_LABELS[status.to_s],
                tickets: tickets.map { |ticket| card(ticket) }
              }
            end
          }
        end

        private

        def card(ticket)
          ideation = ticket.fields_for('ideation') || {}
          creatives = ready_creatives(ticket)
          {
            id: ticket.id,
            title: ticket.display_title,
            status: ticket.status,
            status_label: Ticket::STATUS_LABELS[ticket.status],
            channels: ticket.channels,
            creative_types: ticket.creative_types_list,
            objective: ideation['objective'],
            brief: ideation['brief'],
            scheduled_at: ticket.scheduled_at&.iso8601,
            subtasks_count: ticket.subtasks.size,
            subtasks_done: ticket.subtasks.count(&:done),
            creatives_count: creatives.size,
            # The actual finished deliverables the client can preview in the
            # read-only detail (an in-flight/failed generation is never shown).
            creatives: serialize_collection(creatives, CreativeSerializer)
          }
        end

        # Finished creatives only, ordered stably for the client's review.
        def ready_creatives(ticket)
          ticket.creatives
                .select { |c| c.status.to_s == 'ready' && c.assets.attached? }
                .sort_by { |c| [c.creative_type.to_s, c.id] }
        end
      end
    end
  end
end
