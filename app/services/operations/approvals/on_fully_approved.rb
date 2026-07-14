# frozen_string_literal: true

module Operations
  module Approvals
    # Reached when every approvable creative on a ticket is approved. Records the
    # "Aprovado por <actor>" note, pre-fills a reasonable schedule, and ALWAYS
    # advances the ticket out of Aprovação into the Publication phase (approval →
    # scheduled). Only when the project auto-publishes does it also create the
    # scheduled posts hands-off; otherwise the team confirms in the Publication
    # phase (PostingPanel).
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

        # Only the hands-off branch actually creates the posts here.
        AutoPublishApproved.call(ticket: @ticket) if @ticket.project.setting('auto_publish_after_approval')
        @ticket
      end
    end
  end
end
