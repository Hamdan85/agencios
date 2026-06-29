# frozen_string_literal: true

class MeetingSerializer < ActiveModel::Serializer
  attributes :id, :title, :starts_at, :ends_at, :google_event_id, :meet_url,
             :attendees, :notes, :client_id, :client_name, :project_id,
             :project_name, :created_at

  def starts_at = object.starts_at&.iso8601
  def ends_at = object.ends_at&.iso8601
  def client_name = object.client&.name
  def project_name = object.project&.name
  def created_at = object.created_at&.iso8601
end
