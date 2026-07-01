# frozen_string_literal: true

module Controllers
  module Meetings
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        meeting = workspace.meetings.find(@params[:id])
        Operations::Meetings::RemoveFromCalendar.call(meeting)
        meeting.destroy!
        { message: 'Reunião removida.' }
      end
    end
  end
end
