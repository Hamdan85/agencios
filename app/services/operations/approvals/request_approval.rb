# frozen_string_literal: true

module Operations
  module Approvals
    # Sends (or resends) the client the ticket's approval link and records it.
    # Called by autopilot completion and by the "Reenviar link" action.
    class RequestApproval < Operations::Base
      def initialize(ticket:, sent_by: nil)
        @ticket = ticket
        @sent_by = sent_by
      end

      def call
        @ticket.approval_token! # ensure a token exists (idempotent)
        @ticket.update!(approval_requested_at: Time.current)

        recipients = self.class.recipients_for(@ticket)
        ApprovalMailer.review(ticket: @ticket, recipients: recipients).deliver_later if recipients.any?

        Operations::Notes::Create.call(
          ticket: @ticket, user: @sent_by, kind: :system,
          body: 'Link de aprovação enviado ao cliente.'
        )
        @ticket
      end

      # The client's registered email (recipients are not a project setting).
      def self.recipients_for(ticket)
        Array(ticket.project.client&.email).map(&:to_s).compact_blank.uniq
      end
    end
  end
end
