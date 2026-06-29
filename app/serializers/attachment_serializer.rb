# frozen_string_literal: true

# A ticket file. `url` is the original blob (inline preview + download); for
# images, `preview_url` is a resized variant used as the grid thumbnail. `kind`
# tells the frontend which viewer to render.
class AttachmentSerializer < ActiveModel::Serializer
  attributes :id, :ticket_id, :title, :display_name, :description, :kind,
             :content_type, :filename, :byte_size, :position,
             :url, :preview_url, :uploaded_by, :created_at

  def display_name = object.display_name
  def kind = object.kind
  def byte_size = object.byte_size
  def content_type = object.file.attached? ? object.file.content_type : nil
  def filename = object.file.attached? ? object.file.filename.to_s : nil
  def created_at = object.created_at.iso8601

  def url
    return nil unless object.file.attached?

    blob_url(object.file)
  rescue StandardError
    nil
  end

  # Resized thumbnail for images; nil for everything else (frontend uses an
  # icon). Variants are processed lazily on first access (image_processing/vips).
  def preview_url
    return nil unless object.file.attached? && object.image? && object.file.variable?

    variant = object.file.variant(resize_to_limit: [800, 800], saver: { quality: 80 })
    Rails.application.routes.url_helpers.rails_representation_url(variant, host: SystemConfig.app_host)
  rescue StandardError
    nil
  end

  def uploaded_by
    user = object.uploaded_by
    return nil unless user

    { id: user.id, name: user.display_name }
  end

  private

  def blob_url(attached)
    Rails.application.routes.url_helpers.rails_blob_url(attached, host: SystemConfig.app_host)
  end
end
