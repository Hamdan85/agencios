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
        { meetings: serialize_collection(meetings, MeetingSerializer) }
      end
    end
  end
end
