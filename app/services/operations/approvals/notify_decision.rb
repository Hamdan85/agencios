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
        write_history_note if @history
        notify_responsible
        @ticket
      end

      private

      def approved? = @decision == 'approved'

      def actor_name
        name = @actor.respond_to?(:name) ? @actor.name.to_s : ''
        name.presence || I18n.t('notes.approval.default_actor')
      end

      def subject_label
        return I18n.t('notes.approval.subject_content') unless @creative

        I18n.t('notes.approval.subject_creative', type: @creative.creative_type)
      end

      def write_history_note
        if approved?
          Operations::Notes::Create.call(
            ticket: @ticket, user: nil, kind: :system,
            i18n_key: 'notes.approval.approved',
            i18n_params: { actor: actor_name, subject: subject_label }
          )
        else
          Operations::Notes::Create.call(
            ticket: @ticket, user: nil, kind: :system,
            i18n_key: 'notes.approval.changes_requested',
            i18n_params: { actor: actor_name, subject: subject_label, feedback: @feedback.to_s.truncate(200) }
          )
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
          title_key: approved? ? 'push.approval.approved.title' : 'push.approval.changes_requested.title',
          body_key: approved? ? 'push.approval.approved.body' : 'push.approval.changes_requested.body',
          params: { title: @ticket.display_title, feedback: @feedback.to_s.truncate(120) },
          path: "/tickets/#{@ticket.id}"
        )
      end
    end
  end
end
