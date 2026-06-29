# frozen_string_literal: true

module Controllers
  module Tasks
    # My Tasks (/tarefas, /minhas-tarefas): the current user's subtasks across
    # tickets — paginated (infinite scroll), searchable, and split by tab
    # (pending / overdue / completed). Counts reflect the active search.
    class Index < Base
      DEFAULT_PER = 30

      def initialize(params:)
        @params = params
      end

      def call
        searched = apply_search(scope)
        records, meta = paginate(ordered(apply_tab(searched)), @params, default_per: DEFAULT_PER)
        {
          tasks: serialize_collection(records, MyTaskSerializer),
          counts: counts(searched),
          meta: meta
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

      def apply_search(rel)
        return rel if @params[:q].blank?

        like = "%#{escape_like(@params[:q])}%"
        rel.joins(ticket: :project).where(
          "subtasks.title ILIKE :q OR tickets.title ILIKE :q OR projects.name ILIKE :q", q: like
        )
      end

      def apply_tab(rel)
        case @params[:tab].to_s
        when "overdue"
          rel.where(done: false).where.not(due_date: nil).where("subtasks.due_date < ?", Date.current)
        when "completed"
          rel.where(done: true)
        else # pending (not done, not overdue)
          rel.where(done: false).where("subtasks.due_date IS NULL OR subtasks.due_date >= ?", Date.current)
        end
      end

      # Soonest due first (undated last); most recent first within completed.
      def ordered(rel)
        if @params[:tab].to_s == "completed"
          rel.order(Arel.sql("subtasks.updated_at DESC"))
        else
          rel.order(Arel.sql("subtasks.due_date ASC NULLS LAST, subtasks.created_at ASC"))
        end
      end

      def counts(rel)
        pending = rel.where(done: false)
        {
          pending: pending.where("subtasks.due_date IS NULL OR subtasks.due_date >= ?", Date.current).count,
          overdue: pending.where.not(due_date: nil).where("subtasks.due_date < ?", Date.current).count,
          completed: rel.where(done: true).count
        }
      end
    end
  end
end
