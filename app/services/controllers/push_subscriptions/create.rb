# frozen_string_literal: true

module Controllers
  module PushSubscriptions
    # Stores (or refreshes) the current user's browser push subscription, then
    # fires a one-off confirmation push so the user immediately sees that
    # notifications are working.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        sub = user.push_subscriptions.find_or_initialize_by(endpoint: @params.require(:endpoint))
        sub.update!(
          p256dh_key: @params.require(:p256dh_key),
          auth_key:   @params.require(:auth_key)
        )

        PushNotificationJob.perform_later(
          user.id,
          title: "Notificações ativadas ✅",
          body:  "Você vai receber avisos de tickets, prazos e publicações aqui.",
          path:  "/painel"
        )

        { ok: true }
      end
    end
  end
end
