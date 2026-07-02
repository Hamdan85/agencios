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
          body: "Falha ao publicar em #{provider}: #{@reason}"
        )
        # Put the ticket in alert + generate a task carrying the failure context.
        Operations::Tickets::RaiseAlert.call(
          ticket: @post.ticket,
          reason: "Falha ao publicar em #{provider}: #{@reason[0, 160]}",
          task_title: "Resolver publicação em #{provider}"
        )
        Broadcaster.ticket(@post.ticket, 'post_failed', post_id: @post.id)
        notify("Falha ao publicar em #{provider}", @post.ticket.title)
        email { |to| PostMailer.failed(post: @post, recipient: to, reason: @reason) }
        @post
      end

      private

      def notify(title, body)
        Operations::Push::Notify.call(
          user: @post.ticket.assignee || @post.ticket.created_by,
          title:, body:, path: "/tickets/#{@post.ticket_id}"
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
