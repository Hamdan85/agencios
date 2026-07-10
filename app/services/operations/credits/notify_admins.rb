# frozen_string_literal: true

module Operations
  module Credits
    # Alerts a workspace's owner/admins that a credit-dependent action can't run
    # for lack of credits (e.g. a client-requested regeneration). Idempotent per
    # workspace within a short window so retries / repeated feedback don't spam.
    class NotifyAdmins < Operations::Base
      DEDUPE_WINDOW = 6.hours

      def initialize(workspace:, required:, context: nil)
        @workspace = workspace
        @required = required.to_i
        @context = context
      end

      def call
        return if recently_notified?

        admins.each do |user|
          CreditAlertMailer.insufficient(
            workspace: @workspace, recipient: user, required: @required, context: @context
          ).deliver_later
          Operations::Push::Notify.call(
            user: user, title_key: 'push.insufficient_credits.title',
            body_key: @context ? 'push.insufficient_credits.body_with_context' : 'push.insufficient_credits.body',
            params: { context: @context.to_s },
            path: '/assinatura'
          )
        end
        mark_notified!
        true
      end

      private

      # Owner + admins of the workspace (the people who can buy credits).
      def admins
        @workspace.memberships.where(role: %i[owner admin]).includes(:user).filter_map(&:user).uniq
      end

      def cache_key = "credit_alert:#{@workspace.id}"
      def recently_notified? = Rails.cache.read(cache_key).present?
      def mark_notified! = Rails.cache.write(cache_key, Time.current.to_i, expires_in: DEDUPE_WINDOW)
    end
  end
end
