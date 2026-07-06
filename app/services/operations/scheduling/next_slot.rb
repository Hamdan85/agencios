# frozen_string_literal: true

module Operations
  module Scheduling
    # Pure computation: pick a "reasonable" publish moment for a ticket, given the
    # project's posting window and its already-scheduled posts. Keeps the desired
    # date when it is in the future and collision-free; otherwise returns the
    # earliest window slot >= max(now, desired) that respects the min-gap against
    # the project's other scheduled posts. Searches up to HORIZON_DAYS ahead.
    class NextSlot < Operations::Base
      HORIZON_DAYS = 60

      def initialize(project:, desired_at:)
        @project = project
        @desired_at = desired_at
      end

      def call
        return @desired_at if @desired_at.present? && @desired_at.future? && !collides?(@desired_at)

        lower = [Time.current, @desired_at].compact.max
        scan_from(lower) || lower
      end

      private

      def window = @window ||= @project.setting('posting_window') || {}
      def zone   = @zone ||= (ActiveSupport::TimeZone[window['timezone']] || Time.zone)
      def weekdays = Array(window['weekdays']).map(&:to_i)
      def times    = Array(window['times'])
      def gap      = window['min_gap_minutes'].to_i.minutes

      def scan_from(lower)
        start_date = lower.in_time_zone(zone).to_date
        (0..HORIZON_DAYS).each do |offset|
          date = start_date + offset
          next unless weekdays.include?(date.wday)

          times.sort.each do |hhmm|
            h, m = hhmm.split(':').map(&:to_i)
            slot = zone.local(date.year, date.month, date.day, h, m)
            next if slot < lower
            next if collides?(slot)

            return slot
          end
        end
        nil
      end

      # A candidate collides if any of the project's scheduled posts sits within
      # `gap` of it.
      def collides?(candidate)
        return false if gap.zero?

        scheduled_times.any? { |t| (t - candidate).abs < gap }
      end

      def scheduled_times
        @scheduled_times ||= Post
                             .where(ticket_id: @project.tickets.select(:id))
                             .status_scheduled
                             .where.not(scheduled_at: nil)
                             .pluck(:scheduled_at)
      end
    end
  end
end
