# frozen_string_literal: true

require "google/apis/calendar_v3"
require "googleauth"

module Vendors
  module Google
    # Google Calendar + Meet for meetings. Uses the connecting workspace's
    # encrypted Google tokens (on Setting). App OAuth client from credentials.
    class Calendar < Vendors::Base
      CalendarV3 = ::Google::Apis::CalendarV3

      def initialize(setting:)
        @setting = setting
      end

      def configured?
        @setting&.google_access_token.present?
      end

      # Creates/updates the event (with a Meet link) and returns
      # { google_event_id:, meet_url: }.
      def upsert_event(meeting)
        return stub_event unless configured?

        event = build_event(meeting)
        result =
          if meeting.google_event_id.present?
            service.update_event("primary", meeting.google_event_id, event, conference_data_version: 1)
          else
            service.insert_event("primary", event, conference_data_version: 1)
          end

        { google_event_id: result.id, meet_url: meet_url_from(result) }
      end

      def delete_event(meeting)
        return if meeting.google_event_id.blank? || !configured?

        service.delete_event("primary", meeting.google_event_id)
      rescue ::Google::Apis::ClientError
        nil
      end

      private

      def build_event(meeting)
        CalendarV3::Event.new(
          summary: meeting.title,
          description: meeting.notes,
          start: CalendarV3::EventDateTime.new(date_time: meeting.starts_at.iso8601),
          end: CalendarV3::EventDateTime.new(date_time: (meeting.ends_at || meeting.starts_at + 1.hour).iso8601),
          attendees: Array(meeting.attendees).filter_map { |a| email = a["email"] || a[:email]; CalendarV3::EventAttendee.new(email: email) if email },
          conference_data: CalendarV3::ConferenceData.new(
            create_request: CalendarV3::CreateConferenceRequest.new(
              request_id: SecureRandom.uuid,
              conference_solution_key: CalendarV3::ConferenceSolutionKey.new(type: "hangoutsMeet")
            )
          )
        )
      end

      def meet_url_from(event)
        event.conference_data&.entry_points&.find { |e| e.entry_point_type == "video" }&.uri ||
          event.hangout_link
      end

      def service
        @service ||= CalendarV3::CalendarService.new.tap do |svc|
          svc.authorization = ::Google::Auth::UserRefreshCredentials.new(
            client_id: credential(:google, :client_id, env: "GOOGLE_CLIENT_ID"),
            client_secret: credential(:google, :client_secret, env: "GOOGLE_CLIENT_SECRET"),
            access_token: @setting.google_access_token,
            refresh_token: @setting.google_refresh_token,
            scope: "https://www.googleapis.com/auth/calendar"
          )
        end
      end

      # Local/dev fallback when Google isn't connected — keeps the calendar usable.
      def stub_event
        { google_event_id: "evt_#{SecureRandom.hex(8)}",
          meet_url: "https://meet.google.com/#{SecureRandom.hex(3)}-#{SecureRandom.hex(3)}" }
      end
    end
  end
end
