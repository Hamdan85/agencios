# frozen_string_literal: true

module Controllers
  module Meetings
    # Meetings are personal: by default the list is scoped to the current user
    # (owned or included as attendee). Passing `client_id` switches to the
    # client's FULL history — the client page shows every meeting anyone on the
    # team scheduled with that client (read-only unless you own it).
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        meetings = base_scope.includes(:client, :project, :user).order(:starts_at)
        meetings = meetings.where(starts_at: @params[:from]..) if @params[:from].present?
        meetings = meetings.where(starts_at: ..@params[:to]) if @params[:to].present?
        if @params[:q].present?
          like = "%#{escape_like(@params[:q])}%"
          meetings = meetings.where('meetings.title ILIKE :q OR meetings.notes ILIKE :q', q: like)
        end
        { meetings: serialize_collection(meetings, MeetingSerializer) }
      end

      private

      def base_scope
        if @params[:client_id].present?
          workspace.meetings.where(client_id: @params[:client_id])
        else
          workspace.meetings.involving(user)
        end
      end
    end
  end
end
