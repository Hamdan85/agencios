# frozen_string_literal: true

module Api
  module V1
    class PostsController < BaseController
      def index     = render_ok(Controllers::Posts::Index.call(params:))
      def overview  = render_ok(Controllers::Posts::Overview.call(params:))
      def show      = render_ok(Controllers::Posts::Show.call(params:))
      def create    = render_created(Controllers::Posts::Create.call(params:))
      def update    = render_ok(Controllers::Posts::Update.call(params:))
      def destroy   = render_ok(Controllers::Posts::Destroy.call(params:))

      # POST /api/v1/tickets/:ticket_id/posts/:id/unpublish
      def unpublish = render_ok(Controllers::Posts::Unpublish.call(params:))
    end
  end
end
