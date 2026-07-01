# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      allow_unauthenticated_access only: %i[create]
      # Login/logout must always work, regardless of billing state.
      skip_billing_gate

      def create
        authenticated = Controllers::Sessions::Create.call(email: params[:email], password: params[:password])
        return render_error("E-mail ou senha inválidos.", status: :unauthorized) unless authenticated

        # Cookie/session lifecycle is an HTTP concern owned by the controller.
        start_new_session_for(authenticated)
        resume_session
        render_ok(Controllers::Me::Show.call(include_membership: false))
      end

      def destroy
        terminate_session
        render_ok(message: "Sessão encerrada.")
      end
    end
  end
end
