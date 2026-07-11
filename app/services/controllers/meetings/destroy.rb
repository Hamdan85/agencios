# frozen_string_literal: true

module Controllers
  module Meetings
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        meeting = workspace.meetings.find(@params[:id])
        authorize!(meeting, :destroy?)
        Operations::Meetings::RemoveFromCalendar.call(meeting)
        meeting.destroy!
        { message: I18n.t('api.meetings.removed') }
      end
    end
  end
end
