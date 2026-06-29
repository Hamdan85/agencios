# frozen_string_literal: true

# A dated snapshot of one post's network analytics.
class PostMetric < ApplicationRecord
  belongs_to :post

  scope :recent, -> { order(captured_at: :desc) }

  def engagement = likes.to_i + comments.to_i + shares.to_i + saves.to_i
end
