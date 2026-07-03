# frozen_string_literal: true

module Controllers
  module Meetings
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        meeting = workspace.meetings.find(@params[:id])
        authorize!(meeting, :update?)

        attrs = meeting_params.to_h
        if attrs.key?('attendees')
          attrs['attendees'] = Operations::Meetings::ResolveAttendees.call(attrs['attendees'], workspace: workspace)
        end
        meeting.update!(attrs)

        # Edits must reach the owner's Google Calendar too (new time, attendees…).
        Operations::Meetings::SyncToCalendar.call(meeting)

        { meeting: serialize(meeting, MeetingSerializer) }
      end

      private

      def meeting_params
        @params.require(:meeting).permit(
          :title, :starts_at, :ends_at, :notes, :client_id, :project_id,
          attendees: %i[email name user_id]
        )
      end
    end
  end
end
