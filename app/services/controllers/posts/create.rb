# frozen_string_literal: true

module Controllers
  module Posts
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        # The post may only target a network the ticket's client has connected.
        account = ticket.project.client.social_accounts.find(@params.require(:post).require(:social_account_id))
        post = Operations::Posts::Create.call(
          ticket: ticket,
          social_account: account,
          scheduled_at: @params.dig(:post, :scheduled_at),
          caption: @params.dig(:post, :caption)
        )
        { post: serialize(post, PostSerializer) }
      end
    end
  end
end
