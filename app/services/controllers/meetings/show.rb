# frozen_string_literal: true

module Controllers
  module Meetings
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        meeting = workspace.meetings.find(@params[:id])
        authorize!(meeting, :show?)
        { meeting: serialize(meeting, MeetingSerializer) }
      end
    end
  end
end
