# frozen_string_literal: true

module Operations
  module Approvals
    # The client approves ONE media-type slot of a ticket, choosing the winning
    # option: the chosen creative → approved, its siblings in the slot →
    # not_selected (they leave the portal and never publish). Writes a granular
    # history note. When this was the LAST pending slot, the ticket is fully
    # approved → notify the responsible user + defer OnFullyApproved past the undo
    # window (same deferral/undo semantics as before, now at the ticket level).
    class ApproveSlot < Operations::Base
      UNDO_WINDOW = 6.seconds

      def initialize(ticket:, creative_type:, actor:, chosen_creative_id: nil)
        @ticket = ticket
        @creative_type = creative_type.to_s
        @actor = actor
        @chosen_creative_id = chosen_creative_id
      end

      def call
        options = @ticket.approval_slots[@creative_type]
        raise Operations::Errors::Invalid, 'Peça não encontrada para aprovação.' if options.blank?

        winner = pick_winner(options)
        winner.update!(approval_state: 'approved', reviewed_by: @actor, decided_at: Time.current, client_feedback: nil)
        (options - [winner]).each do |loser|
          loser.update!(approval_state: 'not_selected', reviewed_by: @actor, decided_at: Time.current)
        end

        Broadcaster.ticket(@ticket, 'approval_updated', creative_type: @creative_type, decision: 'approved')
        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :system,
                                       body: "#{actor_name} aprovou #{slot_label}.")

        finalize_if_fully_approved
        @ticket
      end

      private

      def pick_winner(options)
        if @chosen_creative_id.present?
          winner = options.find { |o| o.id.to_s == @chosen_creative_id.to_s }
          raise Operations::Errors::Invalid, 'Opção escolhida não encontrada.' unless winner

          winner
        elsif options.one?
          options.first # single-option slot: the choice is implicit
        else
          raise Operations::Errors::Invalid, 'Escolha uma opção para aprovar esta peça.'
        end
      end

      # When every slot now has an approved winner, the ticket is done: notify the
      # responsible user (email+push, no extra note) and defer the advance so the
      # client can still undo.
      def finalize_if_fully_approved
        return unless @ticket.reload.fully_approved?

        NotifyDecision.call(ticket: @ticket, decision: 'approved', actor: @actor, history: false)
        OnFullyApprovedJob.set(wait: UNDO_WINDOW).perform_later(@ticket.id)
      end

      def slot_label = ::Creatives.spec_for(@creative_type)&.dig(:label) || @creative_type

      def actor_name
        name = @actor.respond_to?(:name) ? @actor.name.to_s : ''
        name.presence || 'Cliente'
      end
    end
  end
end
