# frozen_string_literal: true

module Operations
  module Approvals
    # Records one creative's approval decision (from the client link or an
    # internal actor), then re-evaluates whether the ticket is fully approved.
    class DecideCreative < Operations::Base
      DECISIONS = %w[approved changes_requested].freeze

      def initialize(creative:, decision:, actor:, feedback: nil)
        @creative = creative
        @decision = decision.to_s
        @actor = actor
        @feedback = feedback
      end

      def call
        raise Operations::Errors::Invalid, 'Decisão inválida.' unless DECISIONS.include?(@decision)

        @creative.update!(
          approval_state: @decision, reviewed_by: @actor, decided_at: Time.current,
          client_feedback: (@decision == 'changes_requested' ? @feedback.to_s.presence : nil)
        )

        ticket = @creative.ticket
        Broadcaster.ticket(ticket, 'approval_updated', creative_id: @creative.id, decision: @decision)

        if @decision == 'changes_requested'
          notify_changes(ticket)
        elsif ticket.reload.fully_approved?
          OnFullyApproved.call(ticket: ticket)
        end
        @creative
      end

      private

      def notify_changes(ticket)
        actor_name = @actor.respond_to?(:name) ? @actor.name : 'Cliente'
        Operations::Notes::Create.call(
          ticket: ticket, user: nil, kind: :system,
          body: "#{actor_name} pediu ajustes em um criativo: #{@feedback.to_s.truncate(200)}"
        )
      end
    end
  end
end
