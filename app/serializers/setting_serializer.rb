# frozen_string_literal: true

class SettingSerializer < ActiveModel::Serializer
  attributes :id, :brand_tone, :auto_publish_default, :google_connected,
             :mercadopago_connected, :preferences

  def google_connected = object.google_connected?
  def mercadopago_connected = object.mercadopago_connected?
end
