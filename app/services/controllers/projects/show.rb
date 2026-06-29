# frozen_string_literal: true

module Controllers
  module Projects
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        project = workspace.projects.find(@params[:id])
        authorize!(project, :show?)
        {
          project: serialize(project, ProjectSerializer),
          tickets: serialize_collection(filtered_tickets(project), TicketCardSerializer)
        }
      end

      private

      # Tickets for this project, optionally narrowed by the page's filter set
      # (status, assignee, channel, creative type). Project/client filters are
      # implicit on a single-project page, so they are intentionally absent.
      def filtered_tickets(project)
        scope = project.tickets.active.includes(:project, :assignee, :subtasks, :creatives)
        scope = scope.where(status: @params[:status]) if @params[:status].present?
        scope = scope.where(assignee_id: @params[:assignee_id]) if @params[:assignee_id].present?
        scope = scope.where(creative_type: @params[:creative_type]) if @params[:creative_type].present?
        scope = scope.where("? = ANY(channels)", @params[:channel]) if @params[:channel].present?
        if @params[:q].present?
          like = "%#{escape_like(@params[:q])}%"
          scope = scope.where("tickets.title ILIKE :q OR tickets.creative_type ILIKE :q", q: like)
        end
        scope.board_ordered
      end
    end
  end
end
