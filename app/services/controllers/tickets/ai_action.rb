# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/ai_action — the per-phase "Atualizar campos com IA" action.
    # The Claude rewrite is too slow to hold the request open (it was 502-ing), so
    # this only ENQUEUES the work (Tickets::AiFillJob) and returns immediately. The
    # frontend shimmers the fields and adopts the result when the job broadcasts
    # `ai_fill_done` on `ticket_<id>`.
    class AiAction < Base
      def initialize(params:)
        @params = params
      end

      def call
        # Resolve within the tenant scope so the enqueue is authorized to this
        # workspace's ticket, then hand off by id to the background job.
        ticket = workspace.tickets.find(@params[:id])
        ::Tickets::AiFillJob.perform_later(ticket.id, instruction: @params[:instruction])
        { status: 'queued', ticket_id: ticket.id }
      end
    end
  end
end
