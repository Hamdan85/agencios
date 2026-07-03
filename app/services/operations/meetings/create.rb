# frozen_string_literal: true

module Operations
  module Meetings
    # Creates a Meeting owned by the scheduling user, then syncs it to THEIR
    # Google Calendar. Attendees mix workspace members ({ user_id: }) and
    # external guests ({ email:, name: }) — member entries are resolved to
    # their user's email/name so the Calendar invite reaches everyone.
    class Create < Operations::Base
      PERMITTED = %i[client_id project_id title starts_at ends_at notes attendees].freeze

      def initialize(params, user: Current.user)
        @params = params.to_h.symbolize_keys.slice(*PERMITTED)
        @user = user
      end

      def call
        meeting = workspace.meetings.new(@params)
        meeting.user = @user
        meeting.attendees = Operations::Meetings::ResolveAttendees.call(meeting.attendees, workspace: workspace)
        meeting.save!

        Operations::Meetings::SyncToCalendar.call(meeting)
        notify_attendees(meeting)

        meeting
      end

      private

      # Email everyone invited — the explicit attendee list plus the linked client.
      def notify_attendees(meeting)
        recipients(meeting).each do |email, name|
          MeetingMailer.invitation(meeting: meeting, recipient_email: email, recipient_name: name).deliver_later
        end
      rescue StandardError => e
        Rails.logger.warn("[Meetings::Create] invitation email failed: #{e.message}")
      end

      # => { "person@example.com" => "Name", ... } deduped, blank addresses dropped.
      def recipients(meeting)
        list = Array(meeting.attendees).filter_map do |a|
          email = (a['email'] || a[:email]).to_s.strip
          [email.downcase, (a['name'] || a[:name]).presence] if email.present?
        end
        list << [meeting.client.email.strip.downcase, meeting.client.name] if meeting.client&.email.present?
        list.to_h
      end
    end
  end
end
