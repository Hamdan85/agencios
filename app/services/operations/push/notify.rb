# frozen_string_literal: true

module Operations
  module Push
    # Single entry point for sending a Web Push to a user from a domain
    # operation. No-ops when there's no recipient, when the recipient is the
    # actor who triggered the event (don't notify yourself), or when the user has
    # no registered subscriptions (so we don't enqueue dead jobs). Failures are
    # swallowed — a notification must never break the operation that fired it.
    class Notify < Operations::Base
      def initialize(user:, title:, body:, path: '/painel', actor: nil)
        @user = user
        @title = title
        @body = body
        @path = path
        @actor = actor
      end

      def call
        return if @user.nil?
        return if @actor && @actor.id == @user.id
        return unless @user.push_subscriptions.exists?

        PushNotificationJob.perform_later(@user.id, title: @title, body: @body, path: @path)
      rescue StandardError => e
        Rails.logger.warn("[Push::Notify] #{e.class}: #{e.message}")
      end
    end
  end
end
