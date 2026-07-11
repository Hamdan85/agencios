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
        # Guarantee the per-client portal token exists so the emailed link always
        # resolves (independent of the async mailer / whether the client has e-mail).
        @ticket.project.client&.approval_token!
        @ticket.update!(approval_requested_at: Time.current)
        # Re-requesting approval reopens the pieces the client had rejected: flip
        # their changes_requested back to pending so they reappear in the portal
        # queue awaiting a fresh decision. Approved winners stay approved.
        reopen_rejected_creatives

        recipients = self.class.recipients_for(@ticket)
        if recipients.any?
          ApprovalMailer.review(ticket: @ticket, recipients: recipients).deliver_later
          note_key = 'notes.approval.link_sent'
        else
          note_key = 'notes.approval.link_not_sent'
        end

        Operations::Notes::Create.call(ticket: @ticket, user: @sent_by, kind: :system, i18n_key: note_key)
        @ticket
      end

      # The client's registered email (recipients are not a project setting).
      def self.recipients_for(ticket)
        Array(ticket.project.client&.email).map(&:to_s).compact_blank.uniq
      end

      private

      def reopen_rejected_creatives
        @ticket.approvable_creatives.select(&:approval_changes_requested?).each do |creative|
          creative.update!(approval_state: 'pending', decided_at: nil, reviewed_by: nil, client_feedback: nil)
        end
      end
    end
  end
end
