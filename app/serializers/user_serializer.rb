# frozen_string_literal: true

class UserSerializer < ActiveModel::Serializer
  attributes :id, :email, :name, :display_name, :staff, :avatar_url,
             :google_connected, :google_calendar_connected

  def display_name = object.display_name
  def google_connected = object.google_connected?
  def google_calendar_connected = object.google_calendar_connected?

  def avatar_url
    return nil unless object.avatar.attached?

    Rails.application.routes.url_helpers.rails_blob_url(object.avatar, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end
end
