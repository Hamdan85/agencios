# frozen_string_literal: true

# The end-of-run audit report for a project (the multi-section deck). Built by
# Operations::Reports::GenerateProjectReport when a project is finalized.
# `data` is the full report document; see that operation for its shape.
class ProjectReport < ApplicationRecord
  belongs_to :project
  belongs_to :workspace

  # The rendered branded PDF of the deck, cached so "reenviar" doesn't re-render.
  # Regenerated whenever the report is regenerated (see Operations::Reports::RenderPdf).
  has_one_attached :pdf

  enum :status, { generating: 0, ready: 1, failed: 2 }, prefix: true

  scope :recent, -> { order(created_at: :desc) }
end
