# frozen_string_literal: true

module Controllers
  module Meetings
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        meeting = workspace.meetings.find(@params[:id])
        meeting.update!(meeting_params)
        { meeting: serialize(meeting, MeetingSerializer) }
      end

      private

      def meeting_params
        @params.require(:meeting).permit(
          :title, :starts_at, :ends_at, :notes, :client_id, :project_id,
          attendees: []
        )
      end
    end
  end
end
