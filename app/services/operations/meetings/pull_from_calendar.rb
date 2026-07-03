# frozen_string_literal: true

module Operations
  module Meetings
    # Reflects edits made directly on Google Calendar back into agencios: for
    # every upcoming meeting whose owner has Calendar connected, fetch the event
    # and adopt its title/times; an event cancelled or deleted on Google removes
    # the meeting here. Google is the source of truth for synced fields — the
    # owner edited it there on purpose.
    #
    # Runs as a scheduled sweep (Meetings::PullFromCalendarJob). Google's push
    # channels (webhooks) need per-user watch registration + weekly renewal;
    # the sweep gets the same result with far less moving machinery.
    class PullFromCalendar < Operations::Base
      def initialize(scope: Meeting.upcoming)
        @scope = scope
      end

      def call
        stats = { updated: 0, removed: 0, checked: 0 }

        @scope.where.not(google_event_id: [nil, '']).includes(:user).find_each do |meeting|
          next unless meeting.user&.google_calendar_connected?

          stats[:checked] += 1
          sync_one(meeting, stats)
        rescue StandardError => e
          Rails.logger.warn("[Meetings::PullFromCalendar] meeting ##{meeting.id}: #{e.message}")
        end

        stats
      end

      private

      def sync_one(meeting, stats)
        calendar = Vendors::Google::Calendar.new(user: meeting.user)
        event = calendar.fetch_event(meeting)

        # Gone or cancelled on Google → remove locally.
        if event.nil? || event.status == 'cancelled'
          meeting.destroy!
          stats[:removed] += 1
          return
        end

        changes = changes_from(meeting, event)
        return if changes.empty?

        meeting.update!(changes)
        stats[:updated] += 1
      end

      def changes_from(meeting, event)
        candidate = {
          title: event.summary.presence,
          starts_at: event.start&.date_time,
          ends_at: event.end&.date_time
        }.compact
        candidate.reject { |key, value| values_match?(meeting.public_send(key), value) }
      end

      def values_match?(current, incoming)
        if current.respond_to?(:to_time) && incoming.respond_to?(:to_time)
          current.to_time.to_i == incoming.to_time.to_i
        else
          current == incoming
        end
      end
    end
  end
end
