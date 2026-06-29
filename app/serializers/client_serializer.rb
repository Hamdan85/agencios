# frozen_string_literal: true

class ClientSerializer < ActiveModel::Serializer
  attributes :id, :name, :company, :email, :phone, :document, :notes,
             :status, :attribution, :positioning, :has_positioning,
             :brand_voice, :default_handle, :brand_primary_color, :brand_secondary_color,
             :logo_url, :default_creator_avatar_url, :has_brand,
             :projects_count, :created_at, :updated_at

  def has_positioning = object.positioning?
  def projects_count = object.projects.count
  def created_at = object.created_at&.iso8601
  def updated_at = object.updated_at&.iso8601

  # True once any brand identity element is set (voice, handle, colors are always
  # present via defaults, so this keys off the explicitly-set fields + assets).
  def has_brand
    object.brand_voice.present? || object.default_handle.present? ||
      object.logo.attached? || object.default_creator_avatar.attached?
  end

  def logo_url = blob_url(object.logo)
  def default_creator_avatar_url = blob_url(object.default_creator_avatar)

  private

  def blob_url(attachment)
    return nil unless attachment.attached?

    Rails.application.routes.url_helpers.rails_blob_url(attachment, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end
end
