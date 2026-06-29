# frozen_string_literal: true

module Operations
  module Tickets
    # Bulk-archive every active ticket in a board column (used to "clear" the
    # Concluído column once work is wrapped). A single UPDATE + one board
    # broadcast — no per-ticket logs, since this is terminal cleanup, not a
    # workflow transition.
    class ClearColumn < Operations::Base
      def initialize(workspace, status, user:)
        @workspace = workspace
        @status = status.to_s
        @user = user
      end

      def call
        validate_status!

        tickets = @workspace.tickets.active.where(status: @status)
        count = tickets.count
        tickets.update_all(archived_at: Time.current, updated_at: Time.current) if count.positive?

        Broadcaster.board(@workspace.id, "column_cleared", status: @status, count: count)
        { status: @status, archived_count: count }
      end

      private

      def validate_status!
        return if Ticket::WORKFLOW.map(&:to_s).include?(@status)

        raise Operations::Errors::Invalid, "Status inválido: #{@status}"
      end
    end
  end
end
