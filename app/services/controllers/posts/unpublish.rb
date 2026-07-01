# frozen_string_literal: true

module Controllers
  module Posts
    # POST /tickets/:ticket_id/posts/:id/unpublish — removes a published post
    # from its network (or records it as manually removable when the network
    # has no delete API).
    class Unpublish < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        post = ticket.posts.find(@params[:id])
        Operations::Posts::Unpublish.call(post: post, user: user)
        { post: serialize(post, PostSerializer) }
      end
    end
  end
end
