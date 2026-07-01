# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < BaseController
      def index   = render_ok(Controllers::Projects::Index.call(params:))
      def show    = render_ok(Controllers::Projects::Show.call(params:))
      def create  = render_created(Controllers::Projects::Create.call(params:))
      def update  = render_ok(Controllers::Projects::Update.call(params:))
      def destroy = render_ok(Controllers::Projects::Destroy.call(params:))
      def start   = render_ok(Controllers::Projects::Start.call(params:))
      def finalize = render_ok(Controllers::Projects::Finalize.call(params:))
      def send_scope = render_ok(Controllers::Projects::SendScope.call(params:))

      # Autopilot ("GO mode") over the whole project — estimate then launch a run
      # per eligible ticket. Blocked if any ticket needs manual creatives.
      def autopilot_estimate = render_ok(Controllers::Autopilot::Estimate.call(params:, target: :project))
      def autopilot_start = render_ok(Controllers::Autopilot::Start.call(params:, target: :project))
    end
  end
end
