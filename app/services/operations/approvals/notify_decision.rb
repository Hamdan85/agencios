# frozen_string_literal: true

module Operations
  module Approvals
    # Records a client approval decision as ticket history and notifies the
    # responsible team member (email + push). Called once per client action
    # (approve a ticket / request changes on a creative), NOT per creative.
    class NotifyDecision < Operations::Base
      def initialize(ticket:, decision:, actor:, creative: nil, feedback: nil, history: true)
        @ticket = ticket
        @decision = decision.to_s
        @actor = actor
        @creative = creative
        @feedback = feedback
        @history = history
      end

      def call
        # `history: false` when the caller already wrote a granular note (e.g. a
        # per-slot approval) and only needs the responsible-user notification.
        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :system, body: note_body) if @history
        notify_responsible
        @ticket
      end

      private

      def approved? = @decision == 'approved'

      def actor_name
        name = @actor.respond_to?(:name) ? @actor.name.to_s : ''
        name.presence || 'Cliente'
      end

      def subject_label
        @creative ? "o criativo (#{@creative.creative_type})" : 'o conteúdo'
      end

      def note_body
        if approved?
          "#{actor_name} aprovou #{subject_label}."
        else
          "#{actor_name} pediu ajustes em #{subject_label}: #{@feedback.to_s.truncate(200)}"
        end
      end

      def notify_responsible
        recipient = @ticket.responsible_user
        return if recipient.nil?

        ApprovalDecisionMailer.decided(
          ticket: @ticket, decision: @decision, recipient: recipient,
          creative: @creative, feedback: @feedback
        ).deliver_later

        Operations::Push::Notify.call(
          user: recipient,
          title: approved? ? 'Conteúdo aprovado ✅' : 'Cliente pediu ajustes ✍️',
          body: "#{@ticket.display_title}: #{approved? ? 'aprovado pelo cliente.' : @feedback.to_s.truncate(120)}",
          path: "/tickets/#{@ticket.id}"
        )
      end
    end
  end
end
