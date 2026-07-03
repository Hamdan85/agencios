# frozen_string_literal: true

module Meetings
  # Scheduled sweep (see config/schedule.yml) reflecting edits made directly on
  # Google Calendar back into agencios — reschedules, renames, cancellations.
  class PullFromCalendarJob < ApplicationJob
    queue_as :low

    def perform
      Operations::Meetings::PullFromCalendar.call
    end
  end
end
