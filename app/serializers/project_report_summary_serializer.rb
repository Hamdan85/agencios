# frozen_string_literal: true

# The lightweight envelope for report lists (no `data` payload).
class ProjectReportSummarySerializer < ActiveModel::Serializer
  attributes :id, :project_id, :status, :period_start, :period_end,
             :overall_score, :generated_at, :created_at

  def period_start = object.period_start&.iso8601
  def period_end = object.period_end&.iso8601
  def generated_at = object.generated_at&.iso8601
  def created_at = object.created_at&.iso8601
  def overall_score = object.overall_score&.to_f
end
