# frozen_string_literal: true

module Operations
  module Posts
    # The terminal failure path for a Post publish, kept OUT of Operations::Posts::
    # Publish so it only runs once the job has decided the failure is final (a
    # permanent error, or all retries exhausted) — never on an attempt that will
    # still be retried. Marks the post failed, records the history note, raises the
    # ticket alert + task, broadcasts, and notifies the owner (push + email).
    #
    # Idempotent: a later successful retry may have already published the post, in
    # which case this is a no-op (we never alarm on an already-live post).
    class MarkPublishFailed < Operations::Base
      def initialize(post:, reason:)
        @post = post
        @reason = reason.to_s
      end

      def call
        return if @post.reload.status_published?

        provider = @post.social_account.provider
        @post.update!(status: :failed, failure_reason: @reason[0, 500])
        Operations::Notes::Create.call(
          ticket: @post.ticket, user: nil, kind: :system,
          i18n_key: 'notes.publish_failed',
          i18n_params: { provider: provider, reason: @reason }
        )
        # Put the ticket in alert + generate a task carrying the failure context.
        # Alert reason + task title are persisted plain text (no key column) — render
        # once in the workspace language.
        alert_reason, alert_task = I18n.with_locale(workspace_locale(@post.ticket.workspace)) do
          [I18n.t('operations.tickets.alert.publish_failed_reason', provider: provider, reason: @reason[0, 160]),
           I18n.t('operations.tickets.alert.publish_failed_task', provider: provider)]
        end
        Operations::Tickets::RaiseAlert.call(
          ticket: @post.ticket,
          reason: alert_reason,
          task_title: alert_task
        )
        Broadcaster.ticket(@post.ticket, 'post_failed', post_id: @post.id)
        notify(provider, @post.ticket.title)
        email { |to| PostMailer.failed(post: @post, recipient: to, reason: @reason) }
        @post
      end

      private

      def workspace_locale(ws)
        I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
      end

      def notify(provider, body)
        Operations::Push::Notify.call(
          user: @post.ticket.assignee || @post.ticket.created_by,
          title_key: 'push.post.failed.title', params: { provider: provider }, body: body,
          path: "/tickets/#{@post.ticket_id}"
        )
      end

      def email
        recipient = @post.ticket.assignee || @post.ticket.created_by
        return if recipient.nil? || recipient.email.blank?

        yield(recipient).deliver_later
      rescue StandardError => e
        Rails.logger.warn("[Posts::MarkPublishFailed] email delivery failed: #{e.message}")
      end
    end
  end
end
