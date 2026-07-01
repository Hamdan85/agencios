# frozen_string_literal: true

module Controllers
  module Invitations
    # Mints a signed invite token (workspace id + email + role) and the accept link.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        raise Operations::Errors::SeatLimitReached unless workspace.within_seat_limit?

        email = @params.require(:email).to_s.strip.downcase
        role  = @params.require(:role)

        token = Token.sign(workspace_id: workspace.id, email: email, role: role)
        link  = "#{SystemConfig.app_host}/convite/#{token}"

        InvitationMailer.invite(
          email: email, role: role, link: link,
          workspace: workspace, inviter: Current.user
        ).deliver_later

        { invitation: { email: email, role: role, token: token, link: link } }
      end
    end
  end
end
