# frozen_string_literal: true

module Controllers
  module Posts
    # POST /tickets/:ticket_id/posts/:id/retry — retries ONE failed publication
    # on its own network. The per-network alternative to re-firing the whole
    # posting step (which would duplicate the posts that already succeeded).
    class Retry < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        post = ticket.posts.find(@params[:id])
        Operations::Posts::Retry.call(post: post)
        { post: serialize(post, PostSerializer) }
      end
    end
  end
end
