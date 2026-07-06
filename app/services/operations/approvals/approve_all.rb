# frozen_string_literal: true

module Operations
  module Approvals
    # The internal "Aprovar" action — a team member approves the whole approvable
    # set on the client's behalf, then the full-approval hook runs once.
    class ApproveAll < Operations::Base
      def initialize(ticket:, actor:)
        @ticket = ticket
        @actor = actor
      end

      def call
        set = @ticket.approvable_creatives
        raise Operations::Errors::Invalid, 'Não há criativos prontos para aprovar.' if set.empty?

        set.each do |creative|
          creative.update!(approval_state: 'approved', reviewed_by: @actor, decided_at: Time.current, client_feedback: nil)
        end
        OnFullyApproved.call(ticket: @ticket.reload)
        @ticket
      end
    end
  end
end
