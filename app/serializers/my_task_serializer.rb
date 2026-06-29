# frozen_string_literal: true

# A subtask enriched with its ticket/project context for the My Tasks screen.
class MyTaskSerializer < ActiveModel::Serializer
  attributes :id, :title, :done, :due_date, :ticket_id, :ticket_title,
             :project_name, :project_color, :workspace_id, :workspace_name, :created_at

  def due_date = object.due_date&.iso8601
  def created_at = object.created_at.iso8601
  def ticket_title = object.ticket&.display_title
  def project_name = object.ticket&.project&.name
  def project_color = object.ticket&.project&.color
  def workspace_name = object.workspace&.name
end
