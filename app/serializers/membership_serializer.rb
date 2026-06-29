# frozen_string_literal: true

class MembershipSerializer < ActiveModel::Serializer
  attributes :id, :role, :user_id, :name, :email, :avatar_url, :created_at

  def name = object.user.display_name
  def email = object.user.email
  def created_at = object.created_at.iso8601

  def avatar_url
    return nil unless object.user.avatar.attached?

    Rails.application.routes.url_helpers.rails_blob_url(object.user.avatar, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end
end
