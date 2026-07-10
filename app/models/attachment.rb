# frozen_string_literal: true

# A generic file uploaded to a ticket (one ActiveStorage file per row). Unlike
# Creative — which is a produced deliverable bound to a `creative_type` spec and
# the generation/metering pipeline — an Attachment is any agency file (brief,
# reference, raw footage, PDF, contract, brand asset) and is available in every
# ticket status. `kind` is derived from the blob and drives the frontend viewer.
class Attachment < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket
  belongs_to :uploaded_by, class_name: 'User', optional: true
  # Set when the file was attached inside a ticket comment.
  belongs_to :note, optional: true

  has_one_attached :file

  # 1 GB ceiling — generous enough for agency raw video, guards against abuse.
  MAX_BYTES = 1.gigabyte

  validate :file_present
  validate :file_within_size_limit

  scope :ordered, -> { order(:position, created_at: :asc) }

  # Coarse classification of the file, used by the frontend to pick a viewer
  # (image lightbox, video/audio player, embedded PDF, or a download card).
  def kind
    return 'file' unless file.attached?

    content_type = file.content_type.to_s
    extension = File.extname(file.filename.to_s).downcase.delete('.')

    return 'image' if content_type.start_with?('image/')
    return 'video' if content_type.start_with?('video/')
    return 'audio' if content_type.start_with?('audio/')
    return 'pdf'   if content_type == 'application/pdf' || extension == 'pdf'
    return 'spreadsheet' if spreadsheet?(content_type, extension)
    return 'presentation' if presentation?(content_type, extension)
    return 'document' if document?(content_type, extension)
    return 'archive' if archive?(content_type, extension)

    'file'
  end

  def image? = kind == 'image'

  def display_name
    title.presence || file.filename.to_s.presence || 'Arquivo'
  end

  def byte_size = file.attached? ? file.blob.byte_size : 0

  private

  def file_present
    errors.add(:file, I18n.t('models.attachment.file_required')) unless file.attached?
  end

  def file_within_size_limit
    return unless file.attached?
    return if file.blob.byte_size.to_i <= MAX_BYTES

    errors.add(:file, 'excede o limite de 1 GB')
  end

  def spreadsheet?(content_type, extension)
    extension.in?(%w[xls xlsx csv ods]) || content_type.include?('spreadsheet') || content_type.include?('excel')
  end

  def presentation?(content_type, extension)
    extension.in?(%w[ppt pptx odp key]) || content_type.include?('presentation') || content_type.include?('powerpoint')
  end

  def document?(content_type, extension)
    extension.in?(%w[doc docx odt rtf txt md pages]) ||
      content_type.include?('word') || content_type.start_with?('text/')
  end

  def archive?(content_type, extension)
    extension.in?(%w[zip rar 7z tar gz]) || content_type.include?('zip') || content_type.include?('compressed')
  end
end
