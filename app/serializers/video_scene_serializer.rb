# frozen_string_literal: true

class VideoSceneSerializer < ActiveModel::Serializer
  attributes :id, :position, :mode, :caption, :prompt, :render_state,
             :duration_seconds, :aspect_ratio, :clip_url, :thumbnail_url, :created_at

  def render_state = object.render_state

  def clip_url
    return nil unless object.clip.attached?

    Rails.application.routes.url_helpers.rails_blob_url(object.clip, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  def thumbnail_url = object.metadata.is_a?(Hash) ? object.metadata['thumbnail_url'] : nil

  def created_at = object.created_at&.iso8601
end
