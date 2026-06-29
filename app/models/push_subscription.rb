# frozen_string_literal: true

# A browser Web Push endpoint registered by a user (one per device/browser).
# Created from the frontend after the user grants notification permission;
# consumed by Vendors::WebPush::Client to deliver push messages.
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true
end
