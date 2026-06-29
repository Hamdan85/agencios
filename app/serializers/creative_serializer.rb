# frozen_string_literal: true

class CreativeSerializer < ActiveModel::Serializer
  attributes :id, :creative_type, :source, :status, :provider, :caption,
             :version, :metadata, :asset_urls, :ticket_id, :created_at

  def source = object.source
  def status = object.status

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
