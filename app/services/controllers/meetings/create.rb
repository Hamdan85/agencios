# frozen_string_literal: true

module Controllers
  module Meetings
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Meeting, :create?)
        meeting = Operations::Meetings::Create.call(meeting_params)
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
