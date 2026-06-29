# frozen_string_literal: true

module Controllers
  module Posts
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        ticket.posts.find(@params[:id]).destroy!
        { message: "Publicação removida." }
      end
    end
  end
end
