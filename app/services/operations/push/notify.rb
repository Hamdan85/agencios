# frozen_string_literal: true

module Operations
  module Push
    # Single entry point for sending a Web Push to a user from a domain
    # operation. Copy is passed as i18n keys + params and rendered at DELIVERY
    # time in the recipient's locale (PushNotificationJob), so a notification is
    # never frozen in the sender's language. No-ops when there's no recipient,
    # when the recipient is the actor who triggered the event (don't notify
    # yourself), or when the user has no registered subscriptions (so we don't
    # enqueue dead jobs). Failures are swallowed — a notification must never
    # break the operation that fired it.
    class Notify < Operations::Base
      def initialize(user:, title_key:, body_key: nil, body: nil, params: {}, path: '/painel', actor: nil)
        @user = user
        @title_key = title_key
        @body_key = body_key
        @body = body # raw dynamic body (e.g. a ticket title) — user data, not copy
        @params = params
        @path = path
        @actor = actor
      end

      def call
        return if @user.nil?
        return if @actor && @actor.id == @user.id
        return unless @user.push_subscriptions.exists?

        PushNotificationJob.perform_later(
          @user.id,
          title_key: @title_key, body_key: @body_key, body: @body,
          params: @params.transform_values(&:to_s), path: @path
        )
      rescue StandardError => e
        Rails.logger.warn("[Push::Notify] #{e.class}: #{e.message}")
      end
    end
  end
end
