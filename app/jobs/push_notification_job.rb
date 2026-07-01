# frozen_string_literal: true

# Delivers a Web Push message to a user's browser subscriptions off the request
# path (the encryption + HTTP fan-out is slow). Silently no-ops if the user is
# gone or VAPID isn't configured.
class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id, title:, body:, path: '/')
    user = User.find_by(id: user_id)
    return unless user

    Vendors::WebPush::Actions::SendToUser.call(user:, title:, body:, path:)
  end
end
