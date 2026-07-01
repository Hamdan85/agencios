# frozen_string_literal: true

module Controllers
  module Meetings
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        meetings = workspace.meetings.includes(:client, :project).order(:starts_at)
        meetings = meetings.where(starts_at: @params[:from]..) if @params[:from].present?
        meetings = meetings.where(starts_at: ..@params[:to]) if @params[:to].present?
        meetings = meetings.where(client_id: @params[:client_id]) if @params[:client_id].present?
        if @params[:q].present?
          like = "%#{escape_like(@params[:q])}%"
          meetings = meetings.where('meetings.title ILIKE :q OR meetings.notes ILIKE :q', q: like)
        end
        { meetings: serialize_collection(meetings, MeetingSerializer) }
      end
    end
  end
end
