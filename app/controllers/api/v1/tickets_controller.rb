# frozen_string_literal: true

module Api
  module V1
    class TicketsController < BaseController
      def index    = render_ok(Controllers::Tickets::Index.call(params:))

      # GET /api/v1/tickets/ids — every ticket id matching the current filters
      # (unpaginated), so "select all" can span beyond the loaded pages.
      def ids      = render_ok(Controllers::Tickets::Ids.call(params:))
      def show     = render_ok(Controllers::Tickets::Show.call(params:))
      def create   = render_created(Controllers::Tickets::Create.call(params:))
      def update   = render_ok(Controllers::Tickets::Update.call(params:))
      def destroy  = render_ok(Controllers::Tickets::Destroy.call(params:))

      # POST /api/v1/tickets/:id/advance  { to_status, position }
      def advance  = render_ok(Controllers::Tickets::Advance.call(params:))
      def request_approval = render_ok(Controllers::Approvals::RequestApproval.call(params:))
      def approve          = render_ok(Controllers::Approvals::Approve.call(params:))

      # POST /api/v1/tickets/:id/publish  { creative_id, mode, scheduled_at }
      def publish  = render_ok(Controllers::Tickets::Publish.call(params:))

      # POST /api/v1/tickets/:id/autopilot_estimate — GO-run credit estimate.
      def autopilot_estimate = render_ok(Controllers::Autopilot::Estimate.call(params:, target: :ticket))

      # POST /api/v1/tickets/:id/autopilot_start  { mode, scheduled_at } — launch GO.
      def autopilot_start = render_ok(Controllers::Autopilot::Start.call(params:, target: :ticket))

      # PATCH /api/v1/tickets/:id/reorder  { position }
      def reorder  = render_ok(Controllers::Tickets::Reorder.call(params:))

      # POST /api/v1/tickets/:id/summarize — regenerate the status summary now.
      def summarize = render_ok(Controllers::Tickets::Summarize.call(params:))

      # POST /api/v1/tickets/:id/ai_action — enqueue the status's AI action (async;
      # the ticket channel broadcasts ai_fill_done/failed when it settles).
      def ai_action = render_accepted(Controllers::Tickets::AiAction.call(params:))

      # POST /api/v1/tickets/:id/generate_subtasks — AI production checklist.
      def generate_subtasks = render_ok(Controllers::Tickets::GenerateSubtasks.call(params:))

      # POST /api/v1/tickets/:id/archive — archive (soft-hide) a single ticket.
      def archive = render_ok(Controllers::Tickets::Archive.call(params:))

      # POST /api/v1/tickets/:id/unarchive — restore an archived ticket.
      def unarchive = render_ok(Controllers::Tickets::Unarchive.call(params:))

      # POST /api/v1/tickets/clear_column  { status } — bulk-archive a column.
      def clear_column = render_ok(Controllers::Tickets::ClearColumn.call(params:))

      # POST /api/v1/tickets/bulk_destroy  { ticket_ids: [...] } — permanently
      # delete the selected tickets (hard delete, not archive).
      def bulk_destroy = render_ok(Controllers::Tickets::BulkDestroy.call(params:))
    end
  end
end
