# frozen_string_literal: true

# The end-of-run audit report for a project (the multi-section deck). Built by
# Operations::Reports::GenerateProjectReport when a project is finalized.
# `data` is the full report document; see that operation for its shape.
class ProjectReport < ApplicationRecord
  belongs_to :project
  belongs_to :workspace

  enum :status, { generating: 0, ready: 1, failed: 2 }, prefix: true

  scope :recent, -> { order(created_at: :desc) }
end
