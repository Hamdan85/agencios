# frozen_string_literal: true

# A creative asset on a ticket. `creative_type` is the registry key (the spec);
# `source` is uploaded vs generated.
class Creative < ApplicationRecord
  belongs_to :workspace
  belongs_to :ticket, optional: true
  belongs_to :parent, class_name: "Creative", optional: true

  has_many :versions, class_name: "Creative", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_one  :generation, dependent: :nullify
  has_many_attached :assets

  enum :source, { uploaded: 0, generated: 1 }, prefix: true
  enum :status, { draft: 0, generating: 1, ready: 2, failed: 3 }, prefix: :status

  validates :creative_type, presence: true

  def spec = Creatives.spec_for(creative_type)
end
