# frozen_string_literal: true

module Operations
  module Approvals
    # Reached when every approvable creative on a ticket is approved. Records the
    # "Aprovado por <actor>" note, pre-fills a reasonable schedule, and ALWAYS
    # advances the ticket out of Aprovação into the Publication phase (approval →
    # scheduled).
    #
    # The scheduled posts are then created hands-off in two cases:
    #   * the project opted into it (`auto_publish_after_approval`), or
    #   * the ticket ran on GO — the client's "yes" is what GO was waiting for, so
    #     the automation resumes and finishes the job (Ticket#autopilot_completed?).
    # Otherwise the team confirms the posting itself (PostingPanel).
    class OnFullyApproved < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        # Guard both conditions: it runs deferred (behind the undo window), so a
        # reverted approval — or one the client bounced back to Produção — must
        # no-op, and it must never advance a ticket that isn't in Aprovação.
        return unless @ticket.approval? && @ticket.fully_approved?

        actor = @ticket.approval_actor
        actor_name = (actor.respond_to?(:name) ? actor.name.presence : nil) || I18n.t('notes.approval.default_actor')
        Operations::Notes::Create.call(
          ticket: @ticket, user: nil, kind: :system,
          i18n_key: 'notes.approval.fully_approved',
          i18n_params: { actor: actor_name }
        )
        Broadcaster.ticket(@ticket, 'approval_completed', actor: actor_name)

        # Reasonable default for the Publication phase (keep planned date if future,
        # else next open window slot). Stored so PostingPanel opens pre-scheduled.
        slot = Operations::Scheduling::NextSlot.call(project: @ticket.project, desired_at: @ticket.scheduled_at)
        @ticket.update!(scheduled_at: slot)

        # ALWAYS enter the Publication phase — never skip it.
        Operations::Tickets::ChangeStatus.call(@ticket, 'scheduled', user: nil, force: true)
        @ticket.reload

        # Only the hands-off branches actually create the posts here.
        AutoPublishApproved.call(ticket: @ticket) if auto_publish?
        @ticket
      end

      private

      def auto_publish?
        @ticket.project.setting('auto_publish_after_approval') || @ticket.autopilot_completed?
      end
    end
  end
end
