# frozen_string_literal: true

module Api
  module V1
    module Public
      # Login-less client approval endpoints. The path token IS the credential;
      # we resolve the ticket + workspace from it and set Current.workspace so the
      # serializers work. No session auth, no billing gate. CSRF still applies to
      # mutations (the SPA meta token satisfies it, as with password_resets).
      class ApprovalsController < BaseController
        allow_unauthenticated_access
        skip_billing_gate
        before_action :resolve_ticket!

        def show            = render_ok(Controllers::Public::Approvals::Show.call(ticket: @ticket))
        def approve         = render_ok(Controllers::Public::Approvals::ApproveCreative.call(ticket: @ticket, params:))
        def request_changes = render_ok(Controllers::Public::Approvals::RequestChanges.call(ticket: @ticket, params:))

        private

        def resolve_ticket!
          @ticket = Ticket.find_by(approval_token: params[:token].to_s)
          raise ActiveRecord::RecordNotFound, 'Link inválido ou expirado.' unless @ticket

          Current.workspace = @ticket.workspace
        end
      end
    end
  end
end
