# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < BaseController
      def index   = render_ok(Controllers::Projects::Index.call(params:))
      def show    = render_ok(Controllers::Projects::Show.call(params:))
      def create  = render_created(Controllers::Projects::Create.call(params:))
      def update  = render_ok(Controllers::Projects::Update.call(params:))
      def destroy = render_ok(Controllers::Projects::Destroy.call(params:))
      def finalize = render_ok(Controllers::Projects::Finalize.call(params:))
    end
  end
end
