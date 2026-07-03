# frozen_string_literal: true

module Controllers
  module Calendar
    # Merges scheduled posts (by scheduled_at) and meetings (by starts_at) into
    # dated events for the calendar view.
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        events = posts.map { |p| post_event(p) } + meetings.map { |m| meeting_event(m) }
        { events: events.sort_by { |e| e[:start] } }
      end

      private

      # When `scope=all_workspaces`, the calendar spans every workspace the user
      # belongs to (the "Meu calendário" view); otherwise it is the active tenant.
      def all_workspaces? = @params[:scope] == 'all_workspaces'

      def workspace_ids
        @workspace_ids ||= all_workspaces? ? user.workspace_ids : [workspace.id]
      end

      def from
        @from ||= parse_time(@params[:from]) || Time.current.beginning_of_month
      end

      def to
        @to ||= parse_time(@params[:to]) || Time.current.end_of_month.end_of_day
      end

      def posts
        Post.where(workspace_id: workspace_ids, scheduled_at: from..to)
            .includes(:workspace, :social_account, ticket: :project)
      end

      # The workspace calendar shows the whole team's meetings; the personal
      # "Meu calendário" (all_workspaces) shows only the ones the user owns or
      # is included in — meetings are user-level.
      def meetings
        scope = Meeting.where(workspace_id: workspace_ids, starts_at: from..to)
        scope = scope.involving(user) if all_workspaces?
        scope.includes(:workspace, :client, :project)
      end

      def post_event(post)
        {
          id: "post-#{post.id}",
          type: 'post',
          title: post.ticket&.display_title || 'Publicação',
          start: post.scheduled_at&.iso8601,
          status: post.status,
          provider: post.social_account&.provider,
          color: post.ticket&.project&.color,
          ticket_id: post.ticket_id,
          workspace_id: post.workspace_id,
          workspace_name: post.workspace&.name
        }
      end

      def meeting_event(meeting)
        {
          id: "meeting-#{meeting.id}",
          type: 'meeting',
          title: meeting.title,
          start: meeting.starts_at&.iso8601,
          end: meeting.ends_at&.iso8601,
          meet_url: meeting.meet_url,
          client_name: meeting.client&.name,
          color: '#22C55E',
          workspace_id: meeting.workspace_id,
          workspace_name: meeting.workspace&.name
        }
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
