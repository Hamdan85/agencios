# frozen_string_literal: true

module Operations
  module Meetings
    # Syncs a meeting to Google Calendar + Meet via Vendors::Google::Calendar.
    # Falls back to a local stub event when the workspace hasn't connected Google
    # (so the calendar stays usable in dev / before integration).
    class SyncToCalendar < Operations::Base
      def initialize(meeting)
        @meeting = meeting
      end

      def call
        calendar = Vendors::Google::Calendar.new(setting: @meeting.workspace.setting)
        result = calendar.upsert_event(@meeting)
        @meeting.update!(google_event_id: result[:google_event_id], meet_url: result[:meet_url])
        @meeting
      rescue StandardError => e
        Rails.logger.warn("[Meetings::SyncToCalendar] meeting ##{@meeting.id}: #{e.message}")
        @meeting
      end
    end
  end
end
