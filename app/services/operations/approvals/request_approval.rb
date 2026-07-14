# frozen_string_literal: true

module Operations
  module Approvals
    # Asks the CLIENT to review the ticket: sends (or resends) the approval link
    # and records it. Fired as the side effect of entering the `approval` status
    # (Operations::Tickets::ChangeStatus) and by the explicit "Reenviar link"
    # action once the ticket is already there — so it never touches the status
    # itself.
    #
    # A project may gate approval INTERNALLY (`require_client_approval` off): the
    # ticket still stops in Aprovação, but nobody is emailed and it stays out of
    # the client portal (`approval_requested_at` is the "we actually asked them"
    # marker the portal queue keys on) — the team approves it themselves.
    class RequestApproval < Operations::Base
      def initialize(ticket:, sent_by: nil)
        @ticket = ticket
        @sent_by = sent_by
      end

      def call
        # Re-requesting approval reopens the pieces the client had rejected: flip
        # their changes_requested back to pending so they reappear in the portal
        # queue awaiting a fresh decision. Approved winners stay approved.
        reopen_rejected_creatives
        return note!('notes.approval.internal_only') unless client_approval_required?

        # Guarantee the per-client portal token exists so the emailed link always
        # resolves (independent of the async mailer / whether the client has e-mail).
        @ticket.project.client&.approval_token!
        @ticket.update!(approval_requested_at: Time.current)

        recipients = self.class.recipients_for(@ticket)
        if recipients.any?
          ApprovalMailer.review(ticket: @ticket, recipients: recipients).deliver_later
          note!('notes.approval.link_sent')
        else
          note!('notes.approval.link_not_sent')
        end
      end

      # The client's registered email (recipients are not a project setting).
      def self.recipients_for(ticket)
        Array(ticket.project.client&.email).map(&:to_s).compact_blank.uniq
      end

      private

      def client_approval_required? = @ticket.project.setting('require_client_approval')

      def note!(key)
        Operations::Notes::Create.call(ticket: @ticket, user: @sent_by, kind: :system, i18n_key: key)
        @ticket
      end

      def reopen_rejected_creatives
        @ticket.approvable_creatives.select(&:approval_changes_requested?).each do |creative|
          creative.update!(approval_state: 'pending', decided_at: nil, reviewed_by: nil, client_feedback: nil)
        end
      end
    end
  end
end
