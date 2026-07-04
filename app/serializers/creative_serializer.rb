# frozen_string_literal: true

class CreativeSerializer < ActiveModel::Serializer
  attributes :id, :name, :creative_type, :source, :status, :provider, :caption,
             :version, :metadata, :asset_urls, :preview_url, :ticket_id, :client_id,
             :client_name, :music, :created_at

  def source = object.source
  def status = object.status

  # The background-music track chosen for a video (mood + royalty-free URL +
  # credit). The composed file has it burned in; the editor plays it under the
  # clip-hop preview (before compose) for continuity. Nil when there's none.
  def music
    params = object.generation&.params || {}
    url = params['music_url']
    return nil if url.blank?

    { mood: params['music_mood'], url: url, title: params['music_title'],
      attribution: params['music_attribution'] }.compact
  end

  def client_id
    object.client_id || object.ticket&.project&.client_id
  end

  def client_name
    object.client&.name || object.ticket&.project&.client&.name
  end

  def asset_urls
    return [] unless object.assets.attached?

    object.assets.map do |asset|
      Rails.application.routes.url_helpers.rails_blob_url(asset, host: SystemConfig.app_host)
    end
  rescue StandardError
    []
  end

  # Early visual while a video is still generating: the first rendered scene's
  # clip (cards show its first frame), so the card isn't a blind spinner until
  # the final compose. Nil once real assets exist (asset_urls wins).
  def preview_url
    return nil if object.assets.attached?

    scene = object.video_scenes.detect { |s| s.clip.attached? }
    return nil unless scene

    Rails.application.routes.url_helpers.rails_blob_url(scene.clip, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  def created_at = object.created_at&.iso8601
end
