# frozen_string_literal: true

# A creative asset on a ticket. `creative_type` is the registry key (the spec);
# `source` is uploaded vs generated.
class Creative < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket, optional: true
  belongs_to :client, optional: true
  belongs_to :parent, class_name: "Creative", optional: true

  has_many :versions, class_name: "Creative", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_one  :generation, dependent: :nullify
  has_many_attached :assets

  enum :source, { uploaded: 0, generated: 1 }, prefix: true
  enum :status, { draft: 0, generating: 1, ready: 2, failed: 3 }, prefix: :status

  validates :creative_type, presence: true

  def spec = Creatives.spec_for(creative_type)

  # The publishable media kind (image / video / carousel), used to check whether
  # a network supports this creative before posting. Derived from the actual
  # attachments first, then the creative_type / slide metadata.
  def media_kind
    attached = assets.attached? ? assets : []
    return "video" if attached.any? { |a| a.content_type.to_s.start_with?("video/") }

    slides = metadata.is_a?(Hash) ? Array(metadata["slides"]) : []
    image_count = attached.count { |a| a.content_type.to_s.start_with?("image/") }
    return "carousel" if creative_type.to_s == "carousel" || slides.size > 1 || image_count > 1
    return "image" if image_count == 1 || attached.any?

    "text"
  end
end
