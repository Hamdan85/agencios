# frozen_string_literal: true

module Controllers
  module Subtasks
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        Subtask.where(workspace_id: workspace.id).find(@params[:id]).destroy!
        { message: I18n.t('api.subtasks.removed') }
      end
    end
  end
end
