# frozen_string_literal: true

module Api
  module V1
    module Public
      # Login-less per-CLIENT approval portal. The path token is the credential and
      # resolves a Client (one link per client). It lists that client's tickets
      # awaiting approval; decisions act per ticket (approve) or per creative
      # (request changes). No session auth, no billing gate; CSRF still applies to
      # mutations (the SPA meta token satisfies it).
      class ClientApprovalsController < BaseController
        allow_unauthenticated_access
        skip_billing_gate
        before_action :resolve_client!

        def show            = render_ok(Controllers::Public::ClientApprovals::Show.call(client: @client))
        def approve         = render_ok(Controllers::Public::ClientApprovals::ApproveTicket.call(client: @client, params:))
        def request_changes = render_ok(Controllers::Public::ClientApprovals::RequestChanges.call(client: @client, params:))
        def undo            = render_ok(Controllers::Public::ClientApprovals::Undo.call(client: @client, params:))

        private

        def resolve_client!
          token = params[:token].to_s
          # Per-client token (current). Fall back to a legacy per-TICKET token so
          # links sent before the per-client migration still open the client portal.
          @client = Client.find_by(approval_token: token) ||
                    Ticket.find_by(approval_token: token)&.project&.client
          raise ActiveRecord::RecordNotFound, 'Link inválido ou expirado.' unless @client

          Current.workspace = @client.workspace
        end
      end
    end
  end
end
