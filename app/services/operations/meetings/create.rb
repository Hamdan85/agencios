# frozen_string_literal: true

module Operations
  module Meetings
    # Creates a Meeting on the active workspace, then syncs it to Google Calendar.
    class Create < Operations::Base
      PERMITTED = %i[client_id project_id title starts_at ends_at notes attendees].freeze

      def initialize(params)
        @params = params.to_h.symbolize_keys.slice(*PERMITTED)
      end

      def call
        meeting = workspace.meetings.new(@params)
        meeting.save!

        Operations::Meetings::SyncToCalendar.call(meeting)

        meeting
      end
    end
  end
end
