# frozen_string_literal: true

module Controllers
  module Tasks
    # My Tasks (/tarefas): the current user's subtasks across tickets, optionally
    # across all their workspaces.
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        all = scope.ordered.to_a
        done = all.select(&:done)
        pending = all.reject(&:done)
        overdue = pending.select { |s| s.due_date && s.due_date < Date.current }

        {
          tasks: serialize_collection(pending, MyTaskSerializer),
          completed: serialize_collection(done, MyTaskSerializer),
          counts: { pending: pending.size, overdue: overdue.size, completed: done.size }
        }
      end

      private

      def scope
        base =
          if @params[:scope] == "all_workspaces"
            Subtask.where(assignee_id: user.id)
          else
            Subtask.where(workspace_id: workspace.id, assignee_id: user.id)
          end
        base.includes(:workspace, ticket: :project)
      end
    end
  end
end
