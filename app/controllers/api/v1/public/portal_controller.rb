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

        def report_pdf
          result = Controllers::Public::Portal::ReportPdf.call(client: @client, params:)
          send_data result[:bytes], filename: result[:filename], type: 'application/pdf', disposition: 'inline'
        end

        private

        # The portal serves the CLIENT — its language comes from the client
        # record, not a signed-in user. The around_action runs before
        # resolve_client!, so resolve from the token here (memoized by @client).
        def current_locale
          client = @client || client_from_token
          normalize_locale(client&.locale || client&.workspace&.locale)
        end

        def client_from_token
          token = params[:token].to_s
          Client.find_by(approval_token: token) ||
            Ticket.find_by(approval_token: token)&.project&.client
        end

        def resolve_client!
          @client = client_from_token
          raise ActiveRecord::RecordNotFound, I18n.t('api.public.invalid_link') unless @client

          Current.workspace = @client.workspace
        end
      end
    end
  end
end
