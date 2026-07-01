# frozen_string_literal: true

class SettingSerializer < ActiveModel::Serializer
  attributes :id, :brand_tone, :auto_publish_default, :google_connected,
             :mercadopago_connected, :payment_links_available, :preferences

  def google_connected = object.google_connected?
  def mercadopago_connected = object.mercadopago_connected?
  def payment_links_available = object.payment_links_available?
end
