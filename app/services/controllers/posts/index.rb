# frozen_string_literal: true

module Controllers
  module Posts
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        { posts: serialize_collection(ticket.posts.includes(:social_account), PostSerializer) }
      end
    end
  end
end
