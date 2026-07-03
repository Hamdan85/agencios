# frozen_string_literal: true

module Controllers
  module Posts
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        post = ticket.posts.find(@params[:id])

        # Destroying is CANCELING a not-yet-live publication — the cancelable
        # rule (and the refusal for published posts) lives in the operation.
        Operations::Posts::Cancel.call(post: post)
        { message: 'Agendamento cancelado.' }
      end
    end
  end
end
