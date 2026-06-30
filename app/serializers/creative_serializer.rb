# frozen_string_literal: true

class CreativeSerializer < ActiveModel::Serializer
  attributes :id, :name, :creative_type, :source, :status, :provider, :caption,
             :version, :metadata, :asset_urls, :ticket_id, :client_id, :client_name,
             :created_at

  def source = object.source
  def status = object.status

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

  def created_at = object.created_at&.iso8601
end
