# frozen_string_literal: true

module Api
  module V1
    class TicketsController < BaseController
      def index    = render_ok(Controllers::Tickets::Index.call(params:))
      def show     = render_ok(Controllers::Tickets::Show.call(params:))
      def create   = render_created(Controllers::Tickets::Create.call(params:))
      def update   = render_ok(Controllers::Tickets::Update.call(params:))
      def destroy  = render_ok(Controllers::Tickets::Destroy.call(params:))

      # POST /api/v1/tickets/:id/advance  { to_status, position }
      def advance  = render_ok(Controllers::Tickets::Advance.call(params:))

      # POST /api/v1/tickets/:id/publish  { creative_id, mode, scheduled_at }
      def publish  = render_ok(Controllers::Tickets::Publish.call(params:))

      # PATCH /api/v1/tickets/:id/reorder  { position }
      def reorder  = render_ok(Controllers::Tickets::Reorder.call(params:))

      # POST /api/v1/tickets/:id/summarize — regenerate the status summary now.
      def summarize = render_ok(Controllers::Tickets::Summarize.call(params:))

      # POST /api/v1/tickets/:id/ai_action — run the status's AI action.
      def ai_action = render_ok(Controllers::Tickets::AiAction.call(params:))

      # POST /api/v1/tickets/:id/generate_subtasks — AI production checklist.
      def generate_subtasks = render_ok(Controllers::Tickets::GenerateSubtasks.call(params:))

      # POST /api/v1/tickets/:id/archive — archive (soft-hide) a single ticket.
      def archive = render_ok(Controllers::Tickets::Archive.call(params:))

      # POST /api/v1/tickets/:id/unarchive — restore an archived ticket.
      def unarchive = render_ok(Controllers::Tickets::Unarchive.call(params:))

      # POST /api/v1/tickets/clear_column  { status } — bulk-archive a column.
      def clear_column = render_ok(Controllers::Tickets::ClearColumn.call(params:))
    end
  end
end
