# frozen_string_literal: true

class NoteSerializer < ActiveModel::Serializer
  attributes :id, :body, :kind, :user_id, :user_name, :user_avatar_url,
             :mentioned_user_ids, :mentions, :attachments, :created_at

  def created_at = object.created_at.iso8601
  def user_name = object.user&.display_name

  def user_avatar_url
    return nil unless object.user&.avatar&.attached?

    Rails.application.routes.url_helpers.rails_blob_url(object.user.avatar, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  # [{ id, name }] for the mentioned members, used to render mention chips.
  # Resolved from a `{user_id => name}` map when provided (avoids N+1 across a
  # collection); falls back to a scoped query for a single-note response.
  def mentions
    ids = object.mentioned_user_ids
    return [] if ids.blank?

    names = instance_options[:member_names]
    if names
      ids.filter_map { |id| names[id] && { id: id, name: names[id] } }
    else
      object.mentioned_users.map { |u| { id: u.id, name: u.display_name } }
    end
  end

  # Files attached to this comment (also surfaced in the ticket file list).
  def attachments
    return [] if object.attachments.blank?

    object.attachments.map { |a| AttachmentSerializer.new(a).as_json }
  end
end
