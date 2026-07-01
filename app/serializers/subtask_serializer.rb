# frozen_string_literal: true

class SubtaskSerializer < ActiveModel::Serializer
  attributes :id, :title, :done, :due_date, :position, :assignee_id, :assignee_name,
             :ticket_id, :estimate_hours, :overdue, :created_at

  def due_date = object.due_date&.iso8601
  def created_at = object.created_at.iso8601
  def assignee_name = object.assignee&.display_name
  def estimate_hours = object.estimate_hours&.to_f
  def overdue = object.overdue?
end
