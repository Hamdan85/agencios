# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /api/v1/tickets/bulk_destroy { ticket_ids: [...] }
    # Permanently deletes the selected tickets. Managers only. Unlike Destroy
    # (which soft-archives a single ticket), this is a hard delete.
    class BulkDestroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        Operations::Tickets::BulkDestroy.call(
          workspace, @params[:ticket_ids], user: user
        )
      end
    end
  end
end
