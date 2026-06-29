# frozen_string_literal: true

module Api
  module V1
    class SubtasksController < BaseController
      def create  = render_created(Controllers::Subtasks::Create.call(params:))
      def update  = render_ok(Controllers::Subtasks::Update.call(params:))
      def destroy = render_ok(Controllers::Subtasks::Destroy.call(params:))

      # PATCH /api/v1/subtasks/:id — global My Tasks toggle (no ticket nesting).
      def update_global = render_ok(Controllers::Subtasks::UpdateGlobal.call(params:))
    end
  end
end
