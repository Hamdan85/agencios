# frozen_string_literal: true

module Api
  module V1
    module Public
      # Login-less client central. The path token is the credential and resolves a
      # Client (the same token the approval portal uses — one link per client).
      # Lists the client's campaigns and exposes each campaign's status-driven
      # views: a read-only board, real-time metrics, and the finalized report.
      # No session auth, no billing gate; read-only (no mutations here — approvals
      # keep their own controller).
      class PortalController < BaseController
        allow_unauthenticated_access
        skip_billing_gate
        before_action :resolve_client!

        def show    = render_ok(Controllers::Public::Portal::Show.call(client: @client, params:))
        def board   = render_ok(Controllers::Public::Portal::Board.call(client: @client, params:))
        def metrics = render_ok(Controllers::Public::Portal::Metrics.call(client: @client, params:))
        def report  = render_ok(Controllers::Public::Portal::Report.call(client: @client, params:))

        private

        def resolve_client!
          token = params[:token].to_s
          @client = Client.find_by(approval_token: token) ||
                    Ticket.find_by(approval_token: token)&.project&.client
          raise ActiveRecord::RecordNotFound, 'Link inválido ou expirado.' unless @client

          Current.workspace = @client.workspace
        end
      end
    end
  end
end
