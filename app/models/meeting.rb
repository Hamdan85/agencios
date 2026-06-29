# frozen_string_literal: true

# A Google Calendar + Meet meeting, surfaced on the calendar alongside posts.
class Meeting < ApplicationRecord
  belongs_to :workspace
  belongs_to :client, optional: true
  belongs_to :project, optional: true

  validates :title, presence: true
  validates :starts_at, presence: true

  scope :upcoming, -> { where(starts_at: Time.current..).order(:starts_at) }
end
