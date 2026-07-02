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
          tickets: serialize_collection(filtered_tickets(project), TicketRowSerializer),
          autopilot: autopilot_state(project)
        }
      end

      private

      # The project-level "GO mode" progress, or nil when no batch is running.
      # Aggregates the child ticket-runs so the project view can render a live
      # progress bar and hide the GO button while it walks.
      def autopilot_state(project)
        batch = project.active_autopilot_batch
        return nil unless batch

        children = AutopilotRun.ticket_runs.where(batch_id: batch.id)
        by_state = children.group(:state).count
        finished = %w[completed failed cancelled].sum { |s| by_state[s].to_i }
        {
          id: batch.id,
          state: batch.state,
          active: batch.active?,
          total: children.count,
          done: finished,
          completed: by_state['completed'].to_i,
          failed: by_state['failed'].to_i
        }
      end

      # Tickets for this project, optionally narrowed by the page's filter set
      # (status, assignee, channel, creative type). Project/client filters are
      # implicit on a single-project page, so they are intentionally absent.
      def filtered_tickets(project)
        scope = project.tickets.active.includes(:assignee, :subtasks, :creatives, :autopilot_runs, project: :client)
        scope = scope.where(status: @params[:status]) if @params[:status].present?
        scope = scope.where(assignee_id: @params[:assignee_id]) if @params[:assignee_id].present?
        scope = scope.where(creative_type: @params[:creative_type]) if @params[:creative_type].present?
        scope = scope.where('? = ANY(channels)', @params[:channel]) if @params[:channel].present?
        if @params[:q].present?
          like = "%#{escape_like(@params[:q])}%"
          scope = scope.where('tickets.title ILIKE :q OR tickets.creative_type ILIKE :q', q: like)
        end
        scope.board_ordered
      end
    end
  end
end
