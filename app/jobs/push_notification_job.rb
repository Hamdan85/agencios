# frozen_string_literal: true

# Delivers a Web Push message to a user's browser subscriptions off the request
# path (the encryption + HTTP fan-out is slow). Copy arrives as i18n keys and is
# rendered here, in the RECIPIENT's locale. Silently no-ops if the user is gone
# or VAPID isn't configured.
class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id, title_key: nil, body_key: nil, title: nil, body: nil, params: {}, path: '/')
    user = User.find_by(id: user_id)
    return unless user

    I18n.with_locale(resolve_locale(user)) do
      args = params.symbolize_keys
      rendered_title = title_key ? I18n.t(title_key, **args) : title
      rendered_body  = body_key ? I18n.t(body_key, **args) : body
      Vendors::WebPush::Actions::SendToUser.call(user:, title: rendered_title, body: rendered_body, path:)
    end
  end

  private

  def resolve_locale(user)
    I18n.available_locales.find { |l| l.to_s == user.locale.to_s } || I18n.default_locale
  end
end
