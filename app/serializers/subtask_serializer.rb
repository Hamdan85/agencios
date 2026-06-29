# frozen_string_literal: true

class SubtaskSerializer < ActiveModel::Serializer
  attributes :id, :title, :done, :due_date, :position, :assignee_id, :assignee_name,
             :ticket_id, :created_at

  def due_date = object.due_date&.iso8601
  def created_at = object.created_at.iso8601
  def assignee_name = object.assignee&.display_name
end
