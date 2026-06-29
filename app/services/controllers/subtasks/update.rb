# frozen_string_literal: true

module Controllers
  module Subtasks
    # Update a subtask nested under a ticket.
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        subtask = workspace_subtask(@params[:id])
        subtask.update!(subtask_params)
        { subtask: serialize(subtask, SubtaskSerializer) }
      end

      private

      def workspace_subtask(id)
        Subtask.where(workspace_id: workspace.id).find(id)
      end

      def subtask_params
        @params.require(:subtask).permit(:title, :done, :due_date, :position, :assignee_id)
      end
    end
  end
end
