# frozen_string_literal: true

module Controllers
  module Meetings
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Meeting, :create?)
        meeting = Operations::Meetings::Create.call(meeting_params, user: user)
        { meeting: serialize(meeting, MeetingSerializer) }
      end

      private

      def meeting_params
        # Attendees mix workspace members ({ user_id }) and external guests
        # ({ email, name }).
        @params.require(:meeting).permit(
          :title, :starts_at, :ends_at, :notes, :client_id, :project_id,
          attendees: %i[email name user_id]
        )
      end
    end
  end
end
