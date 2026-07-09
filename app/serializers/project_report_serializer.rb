# frozen_string_literal: true

# The full report deck (the `data` document) plus its envelope. Used by the
# report page.
class ProjectReportSerializer < ActiveModel::Serializer
  attributes :id, :project_id, :status, :period_start, :period_end,
             :overall_score, :data, :generated_at, :created_at,
             :project_name, :client_name, :sent_to_client_at, :client_email

  def period_start = object.period_start&.iso8601
  def period_end = object.period_end&.iso8601
  def generated_at = object.generated_at&.iso8601
  def created_at = object.created_at&.iso8601
  def sent_to_client_at = object.sent_to_client_at&.iso8601
  def overall_score = object.overall_score&.to_f
  def project_name = object.project&.name
  def client_name = object.project&.client&.name
  # Drives the "Enviar ao cliente" button state (disabled when the client has no
  # e-mail); never exposes the address itself beyond presence to internal roles.
  def client_email = object.project&.client&.email
end
