# frozen_string_literal: true

module Operations
  module Tickets
    # Permanently delete a set of tickets (and their dependent records) by id.
    # Scoped to the workspace, so ids belonging to another tenant are silently
    # ignored. Uses destroy_all so `dependent: :destroy` associations cascade. A
    # single board broadcast refreshes any open board / list. This is a hard
    # delete — distinct from Archive, which only soft-hides via `archived_at`.
    class BulkDestroy < Operations::Base
      def initialize(workspace, ticket_ids, user:)
        @workspace = workspace
        @ticket_ids = Array(ticket_ids).map(&:to_s).reject(&:blank?)
        @user = user
      end

      def call
        tickets = @workspace.tickets.where(id: @ticket_ids)
        ids = tickets.pluck(:id)
        tickets.destroy_all if ids.any?

        Broadcaster.board(@workspace.id, "cards_deleted", ticket_ids: ids) if ids.any?
        { deleted_count: ids.size }
      end
    end
  end
end
