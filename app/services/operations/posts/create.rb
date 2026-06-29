# frozen_string_literal: true

module Operations
  module Posts
    # Creates a scheduled Post for a ticket on one connected network. The post is
    # born in `scheduled`; publishing happens later via Operations::Posts::Publish.
    class Create < Operations::Base
      def initialize(ticket:, social_account:, scheduled_at: nil, caption: nil)
        @ticket = ticket
        @social_account = social_account
        @scheduled_at = scheduled_at
        @caption = caption
      end

      def call
        Post.create!(
          workspace_id: @ticket.workspace_id,
          ticket: @ticket,
          social_account: @social_account,
          status: :scheduled,
          scheduled_at: @scheduled_at || @ticket.scheduled_at,
          caption: @caption
        )
      end
    end
  end
end
