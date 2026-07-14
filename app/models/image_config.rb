# frozen_string_literal: true

# Singleton row holding the IMAGE-generation model routing (admin-editable, no
# deploy). Images render through OpenRouter's multimodal chat endpoint — only
# the non-secret model slug lives here; the API key stays in credentials. Read
# through Vendors::OpenRouter::Image. `instance` returns the row, or an unsaved
# defaults-populated record when the table is empty so reads never write
# (mirrors AiConfig / VideoConfig).
class ImageConfig < ApplicationRecord
  def self.instance
    first || new
  end

  # The OpenRouter image slug, or nil to let the client fall back to its own
  # chain (credentials override → coded default).
  def model
    default_model.to_s.strip.presence
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id default_model created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil) = []
end
