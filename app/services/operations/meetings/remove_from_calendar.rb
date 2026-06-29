# frozen_string_literal: true

module Operations
  module Meetings
    # Removes a meeting's Google Calendar event (the counterpart to
    # SyncToCalendar). Safe to call before destroying the meeting; a Google
    # outage must never block the deletion, so it swallows + logs.
    class RemoveFromCalendar < Operations::Base
      def initialize(meeting)
        @meeting = meeting
      end

      def call
        return @meeting if @meeting.google_event_id.blank?

        Vendors::Google::Calendar.new(setting: @meeting.workspace.setting).delete_event(@meeting)
        @meeting
      rescue StandardError => e
        Rails.logger.warn("[Meetings::RemoveFromCalendar] meeting ##{@meeting.id}: #{e.message}")
        @meeting
      end
    end
  end
end
