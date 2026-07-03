# frozen_string_literal: true

# A Google Calendar + Meet meeting, surfaced on the calendar alongside posts.
#
# Meetings are user-level: the owning `user` scheduled it and hosts the event on
# THEIR Google Calendar (tokens on User, connected from the account page). The
# meeting is visible to every team member included as an attendee; only the
# owner may edit or delete it. `attendees` is a jsonb array of
# { email:, name:, user_id? } — team members carry their user_id, external
# guests are plain emails.
class Meeting < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true
  belongs_to :client, optional: true
  belongs_to :project, optional: true

  validates :title, presence: true
  validates :starts_at, presence: true

  scope :upcoming, -> { where(starts_at: Time.current..).order(:starts_at) }

  # Meetings the user owns OR is invited to (matched by attendee user_id or email).
  scope :involving, lambda { |user|
    return none if user.nil?

    where(user_id: user.id)
      .or(where('meetings.attendees @> ?', [{ user_id: user.id }].to_json))
      .or(where('meetings.attendees @> ?', [{ email: user.email.to_s.downcase }].to_json))
  }

  def owned_by?(user) = user.present? && user_id == user.id
end
