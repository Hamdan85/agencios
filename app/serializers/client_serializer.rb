# frozen_string_literal: true

class ClientSerializer < ActiveModel::Serializer
  attributes :id, :name, :company, :email, :phone, :document, :notes,
             :status, :attribution, :positioning, :has_positioning,
             :projects_count, :created_at, :updated_at

  def has_positioning = object.positioning?
  def projects_count = object.projects.count
  def created_at = object.created_at&.iso8601
  def updated_at = object.updated_at&.iso8601
end
