# frozen_string_literal: true

module Api
  module V1
    class PostsController < BaseController
      def index   = render_ok(Controllers::Posts::Index.call(params:))
      def create  = render_created(Controllers::Posts::Create.call(params:))
      def update  = render_ok(Controllers::Posts::Update.call(params:))
      def destroy = render_ok(Controllers::Posts::Destroy.call(params:))
    end
  end
end
