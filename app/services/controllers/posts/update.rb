# frozen_string_literal: true

module Controllers
  module Posts
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        post = ticket.posts.find(@params[:id])
        post.update!(@params.require(:post).permit(:caption, :scheduled_at))
        { post: serialize(post, PostSerializer) }
      end
    end
  end
end
