# frozen_string_literal: true

module Api
  module V1
    # Content-strategy planning sessions (the non-streaming endpoints). The chat
    # turn itself streams over SSE via StrategyMessagesController.
    class StrategySessionsController < BaseController
      # GET  /api/v1/projects/:project_id/strategy_session
      def show   = render_ok(Controllers::Strategy::Show.call(params:))
      # POST /api/v1/projects/:project_id/strategy_session
      def create = render_created(Controllers::Strategy::Create.call(params:))
      # POST /api/v1/strategy_sessions/:id/apply
      def apply  = render_ok(Controllers::Strategy::Apply.call(params:))
      # POST /api/v1/strategy_sessions/:id/discard
      def discard = render_ok(Controllers::Strategy::Discard.call(params:))
    end
  end
end
