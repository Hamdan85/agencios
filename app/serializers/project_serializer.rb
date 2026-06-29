# frozen_string_literal: true

class ProjectSerializer < ActiveModel::Serializer
  attributes :id, :name, :description, :color, :status, :starts_on, :ends_on,
             :budget_cents, :client_id, :client_name, :tickets_count, :created_at

  def starts_on = object.starts_on&.iso8601
  def ends_on = object.ends_on&.iso8601
  def client_name = object.client&.name
  def tickets_count = object.tickets.count
  def created_at = object.created_at&.iso8601
end
