# frozen_string_literal: true

module Controllers
  module Subtasks
    # PATCH /api/v1/subtasks/:id — global My Tasks toggle (no ticket nesting).
    class UpdateGlobal < Base
      def initialize(params:)
        @params = params
      end

      def call
        subtask = Subtask.where(workspace_id: workspace.id).find_by(id: @params[:id])
        raise ActiveRecord::RecordNotFound, 'Subtarefa não encontrada.' unless subtask

        subtask.update!(subtask_params)
        { subtask: serialize(subtask, SubtaskSerializer) }
      end

      private

      def subtask_params
        @params.require(:subtask).permit(:title, :done, :due_date, :position, :assignee_id)
      end
    end
  end
end
