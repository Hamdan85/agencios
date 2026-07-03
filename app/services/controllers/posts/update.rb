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

        # The editable rule (not-live only; failed + new time = retry) lives in
        # the posts' own operation — this stays a thin HTTP shell.
        Operations::Posts::Update.call(post: post, attributes: @params.require(:post).permit(:caption, :scheduled_at))
        { post: serialize(post.reload, PostSerializer) }
      end
    end
  end
end
