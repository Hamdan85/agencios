# frozen_string_literal: true

module Operations
  module Digests
    # Sent once a day to every user with at least one billing-active workspace
    # (see SendDailyTicketDigestJob). Lists the tickets assigned to them, across
    # all of their active workspaces, that are due today or overdue.
    class SendDailyTicketDigest < Operations::Base
      def initialize(user:)
        @user = user
      end

      def call
        return if @user.email.blank?

        active_workspaces = @user.workspaces.select(&:billing_active?)
        return if active_workspaces.empty?

        DigestMailer.daily_tickets(user: @user, tickets: tickets_for(active_workspaces)).deliver_later
      end

      private

      def tickets_for(active_workspaces)
        Ticket
          .where(workspace_id: active_workspaces.map(&:id), assignee_id: @user.id)
          .active
          .where.not(status: :done)
          .due_or_overdue
          .includes(:workspace, :project)
          .order(:due_date, :scheduled_at)
          .to_a
      end
    end
  end
end
