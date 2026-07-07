# frozen_string_literal: true

module Operations
  module Ai
    # Drafts the "lessons learned" retrospective from the ticket's post metrics
    # and note history, writes it into fields.retrospective.lessons_learned, and
    # broadcasts summary_ready. Runs outside a request — resolves everything
    # from the ticket.
    class DraftRetrospective < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        metrics = @ticket.posts.flat_map(&:post_metrics).map(&:engagement).sum
        builder = Prompts::Retrospective.new(
          workspace: @ticket.workspace, client: @ticket.project.client,
          objective: @ticket.fields_for('ideation')['objective'],
          metrics: "engajamento total: #{metrics}",
          history: @ticket.notes.chronological.last(8).map(&:body).join(' | ')
        )
        draft = AiAdapter.complete(
          builder, max_tokens: 600, operation: 'draft_retrospective', subject: @ticket
        ).to_s.strip

        retrospective = @ticket.fields_for('retrospective').merge('lessons_learned' => draft)
        @ticket.update!(fields: @ticket.fields.merge('retrospective' => retrospective))

        Broadcaster.ticket(@ticket, 'summary_ready', status: 'retrospective', summary: draft)
        draft
      end
    end
  end
end
