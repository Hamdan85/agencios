# frozen_string_literal: true

class MeetingSerializer < ActiveModel::Serializer
  attributes :id, :title, :starts_at, :ends_at, :google_event_id, :meet_url,
             :attendees, :notes, :client_id, :client_name, :project_id,
             :project_name, :user_id, :user_name, :user_avatar_url, :created_at

  def starts_at = object.starts_at&.iso8601
  def ends_at = object.ends_at&.iso8601
  def client_name = object.client&.name
  def project_name = object.project&.name
  def created_at = object.created_at&.iso8601

  # The meeting's owner (who scheduled it) — the frontend gates edit/delete on
  # user_id === me.user.id and shows the owner chip on shared listings.
  def user_name = object.user&.name
  def user_avatar_url
    return nil unless object.user&.avatar&.attached?

    Rails.application.routes.url_helpers.rails_blob_url(object.user.avatar, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end
end
