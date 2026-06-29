# frozen_string_literal: true

module Api
  module V1
    # My Tasks (/tarefas): the current user's subtasks across tickets, optionally
    # across all their workspaces.
    class TasksController < BaseController
      def index
        render_ok(Controllers::Tasks::Index.call(params:))
      end
    end
  end
end
