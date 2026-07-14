# frozen_string_literal: true

module Operations
  module Approvals
    # The internal "Aprovar" action — a team member approves on the client's behalf
    # (or approves outright, on a project that gates approval internally). Approves
    # ONE winner per media-type slot (the newest option), marking the rest
    # not_selected, then the full-approval hook runs once.
    #
    # Only valid in Aprovação: approving elsewhere would mark every creative approved
    # while OnFullyApproved refused to advance, stranding the ticket.
    class ApproveAll < Operations::Base
      def initialize(ticket:, actor:)
        @ticket = ticket
        @actor = actor
      end

      def call
        raise Operations::Errors::Invalid, I18n.t('operations.approvals.not_in_approval') unless @ticket.approval?

        slots = @ticket.approval_slots
        raise Operations::Errors::Invalid, I18n.t('operations.approvals.nothing_to_approve') if slots.empty?

        slots.each_value do |options|
          winner = options.max_by { |c| c.created_at || Time.at(0) } # newest option wins
          winner.update!(approval_state: 'approved', reviewed_by: @actor, decided_at: Time.current, client_feedback: nil)
          (options - [winner]).each do |loser|
            loser.update!(approval_state: 'not_selected', reviewed_by: @actor, decided_at: Time.current)
          end
        end
        OnFullyApproved.call(ticket: @ticket.reload)
        @ticket
      end
    end
  end
end
