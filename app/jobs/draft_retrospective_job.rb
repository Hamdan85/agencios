# frozen_string_literal: true

class DraftRetrospectiveJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    metrics = ticket.posts.flat_map(&:post_metrics).map(&:engagement).sum
    builder = Prompts::Retrospective.new(
      workspace: ticket.workspace, client: ticket.project.client,
      objective: ticket.fields_for("ideation")["objective"],
      metrics: "engajamento total: #{metrics}",
      history: ticket.notes.chronological.last(8).map(&:body).join(" | ")
    )
    draft = AiAdapter.complete(
      builder, max_tokens: 600, operation: "draft_retrospective", subject: ticket
    ).to_s.strip

    fields = ticket.fields.merge("retrospective" => ticket.fields_for("retrospective").merge("lessons_learned" => draft))
    ticket.update!(fields: fields)
    Broadcaster.ticket(ticket, "summary_ready", status: "retrospective", summary: draft)
  end
end
